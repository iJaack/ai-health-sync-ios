# Homebrew Tap Setup Guide

This guide explains how to set up the `homebrew-tap` repository for automated formula updates.

## 1. Create the GitHub Repository

Create a new repository on GitHub named `homebrew-tap`:
- Repository name: `homebrew-tap`
- Make it public
- Don't initialize with README (we'll push existing files)

```bash
# From the homebrew-tap directory
cd homebrew-tap
git init
git add .
git commit -m "Initial commit: healthsync formula"
git branch -M main
git remote add origin https://github.com/mneves75/homebrew-tap.git
git push -u origin main
```

## 2. Create Personal Access Token

For the main repo's GitHub Action to update this tap:

1. Go to GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Create new token with:
   - **Name**: `HOMEBREW_TAP_TOKEN`
   - **Repository access**: Only select repositories → `homebrew-tap`
   - **Permissions**:
     - Contents: Read and write
     - Metadata: Read-only

3. Copy the token

## 3. Add Secret to Main Repository

1. Go to `ai-health-sync-ios` repository settings
2. Secrets and variables → Actions
3. New repository secret:
   - **Name**: `HOMEBREW_TAP_TOKEN`
   - **Value**: (paste the token from step 2)

## 4. Test the Workflow

Create a new release:

```bash
# In the main repository
git tag -a v1.0.1 -m "Test release"
git push origin v1.0.1
```

The GitHub Action will:
1. Build arm64 and x86_64 binaries
2. Create a GitHub Release with binaries attached
3. Update this tap's formula with new version and SHA256 hashes

## 5. Verify Installation

```bash
brew tap mneves75/tap
brew install healthsync
healthsync --version
```

## Directory Structure

```
homebrew-tap/
├── Formula/
│   └── healthsync.rb    # Auto-updated by GitHub Action
├── README.md
└── SETUP.md             # This file
```

## Troubleshooting

### Formula Not Updating

Check the GitHub Action logs in the main repository:
1. Go to Actions tab
2. Find the "Release" workflow
3. Check the "Update Homebrew Tap" job

### Permission Denied

Ensure the `HOMEBREW_TAP_TOKEN` has write access to the homebrew-tap repository.

### brew audit Failures

Run locally:
```bash
brew audit --strict Formula/healthsync.rb
```

## Links

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Creating a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)
