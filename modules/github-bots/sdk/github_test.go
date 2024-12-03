package sdk_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/chainguard-dev/terraform-infra-common/modules/github-bots/sdk"
	"github.com/go-git/go-billy/v5/osfs"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/object"
	"github.com/go-git/go-git/v5/storage/memory"
	"github.com/google/go-cmp/cmp"
)

func TestGithubClient_GetChangedFiles(t *testing.T) {
	ctx := context.Background()
	client := sdk.NewGitHubClient(ctx, "org", "repo", "bot")

	tests := []struct {
		name     string
		patches  []gpatch
		expected map[string]struct{}
		wantErr  bool
	}{
		{
			name: "Added file",
			patches: []gpatch{
				{action: "add", path: "new.txt"},
			},
			expected: map[string]struct{}{
				"new.txt": {},
			},
		},
		{
			name: "Modified file",
			patches: []gpatch{
				{action: "add", path: "existing.txt"},
				{action: "modify", path: "existing.txt"},
			},
			expected: map[string]struct{}{
				"existing.txt": {},
			},
		},
		{
			name: "Renamed file",
			patches: []gpatch{
				{action: "add", path: "old.txt"},
				{action: "rename", path: "old.txt", newPath: "new.txt"},
			},
			expected: map[string]struct{}{
				"new.txt": {},
			},
		},
		{
			name: "Deleted file",
			patches: []gpatch{
				{action: "add", path: "to_delete.txt"},
				{action: "delete", path: "initial.txt"},
			},
			expected: map[string]struct{}{
				"to_delete.txt": {},
				"initial.txt":   {},
			},
		},
		{
			name: "Multiple changes",
			patches: []gpatch{
				{action: "add", path: "new.txt"},
				{action: "add", path: "to_modify.txt"},
				{action: "modify", path: "to_modify.txt"},
				{action: "add", path: "to_rename.txt"},
				{action: "rename", path: "to_rename.txt", newPath: "renamed.txt"},
				{action: "add", path: "to_delete.txt"},
				{action: "delete", path: "to_delete.txt"},
			},
			expected: map[string]struct{}{
				"new.txt":       {},
				"to_modify.txt": {},
				"renamed.txt":   {},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := setupTestRepo(t, tt.patches)

			got, err := client.GetChangedFiles(ctx, repo, "feature", "main")
			if (err != nil) != tt.wantErr {
				t.Errorf("GetChangedFiles() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if err != nil {
				t.Logf("Error details: %+v", err)
			}
			if diff := cmp.Diff(got, tt.expected); diff != "" {
				t.Errorf("GetChangedFiles() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}

type gpatch struct {
	action  string
	path    string
	newPath string
}

func setupTestRepo(t *testing.T, patches []gpatch) *git.Repository {
	t.Helper()

	dir := t.TempDir()
	fs := osfs.New(dir)
	repo, err := git.Init(memory.NewStorage(), fs)
	if err != nil {
		t.Fatalf("failed to init git repo: %v", err)
	}

	w, err := repo.Worktree()
	if err != nil {
		t.Fatalf("failed to get worktree: %v", err)
	}

	// Create and commit an initial file on main
	if err := writeFile(w, "initial.txt", "initial content"); err != nil {
		t.Fatalf("failed to create initial file: %v", err)
	}
	if _, err := w.Add("initial.txt"); err != nil {
		t.Fatalf("failed to add initial file: %v", err)
	}
	if _, err := w.Commit("Initial commit", &git.CommitOptions{
		Author: &object.Signature{Name: "Test Author", Email: "test@example.com"},
	}); err != nil {
		t.Fatalf("failed to commit initial file: %v", err)
	}

	// Create main branch
	mainRef := plumbing.NewBranchReferenceName("main")
	headRef, err := repo.Head()
	if err != nil {
		t.Fatalf("failed to get HEAD reference: %v", err)
	}
	if err := repo.Storer.SetReference(plumbing.NewHashReference(mainRef, headRef.Hash())); err != nil {
		t.Fatalf("failed to set main branch reference: %v", err)
	}

	// Create and checkout feature branch
	if err := w.Checkout(&git.CheckoutOptions{
		Create: true,
		Branch: plumbing.NewBranchReferenceName("feature"),
	}); err != nil {
		t.Fatalf("failed to checkout feature branch: %v", err)
	}

	// Apply patches
	for _, p := range patches {
		if err := applyPatch(w, p); err != nil {
			t.Fatalf("failed to apply patch: %v", err)
		}
	}

	// Commit changes
	if _, err := w.Add("."); err != nil {
		t.Fatalf("failed to add changes: %v", err)
	}
	if _, err := w.Commit("Test changes", &git.CommitOptions{
		Author: &object.Signature{Name: "Test Author", Email: "test@example.com"},
	}); err != nil {
		t.Fatalf("failed to commit changes: %v", err)
	}

	// Set up the feature branch reference
	headRef, err = repo.Head()
	if err != nil {
		t.Fatalf("failed to get HEAD reference: %v", err)
	}
	featureRef := plumbing.NewHashReference(plumbing.ReferenceName("refs/heads/feature"), headRef.Hash())
	if err := repo.Storer.SetReference(featureRef); err != nil {
		t.Fatalf("failed to set feature branch reference: %v", err)
	}

	return repo
}

func applyPatch(w *git.Worktree, p gpatch) error {
	switch p.action {
	case "add":
		return writeFile(w, p.path, "content")
	case "modify":
		return writeFile(w, p.path, "modified content")
	case "rename":
		if err := w.Filesystem.Rename(p.path, p.newPath); err != nil {
			return fmt.Errorf("failed to rename file: %w", err)
		}
	case "delete":
		if err := w.Filesystem.Remove(p.path); err != nil {
			return fmt.Errorf("failed to delete file: %w", err)
		}
	}
	return nil
}

func writeFile(w *git.Worktree, path, content string) error {
	f, err := w.Filesystem.Create(path)
	if err != nil {
		return fmt.Errorf("failed to create file %s: %w", path, err)
	}
	defer f.Close()
	if _, err := f.Write([]byte(content)); err != nil {
		return fmt.Errorf("failed to write to file %s: %w", path, err)
	}
	return nil
}
