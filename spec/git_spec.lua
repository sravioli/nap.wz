describe("nap.git", function()
  local git, wez

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    git = require "nap.git"
  end)

  -- ── run ───────────────────────────────────────────────────────

  describe("run", function()
    it("builds correct command with git -C", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      git.run("/path/to/repo", { "status" })
      assert.same({ "git", "-C", "/path/to/repo", "status" }, captured_cmd)
    end)

    it("passes multiple args correctly", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      git.run("/repo", { "log", "--oneline", "abc..def" })
      assert.same({ "git", "-C", "/repo", "log", "--oneline", "abc..def" }, captured_cmd)
    end)

    it("returns success and output on success", function()
      wez.run_child_process = function()
        return true, "output text\n", ""
      end
      local ok, stdout, stderr = git.run("/repo", { "status" })
      assert.is_true(ok)
      assert.equal("output text\n", stdout)
      assert.equal("", stderr)
    end)

    it("returns false and stderr on failure", function()
      wez.run_child_process = function()
        return false, "", "fatal: not a repo\n"
      end
      local ok, stdout, stderr = git.run("/bad", { "status" })
      assert.is_false(ok)
      assert.equal("", stdout)
      assert.equal("fatal: not a repo\n", stderr)
    end)

    it("handles pcall failure gracefully", function()
      wez.run_child_process = function()
        error "git not found"
      end
      local ok, stdout, stderr = git.run("/repo", { "status" })
      assert.is_false(ok)
      assert.equal("", stdout)
      assert.truthy(stderr:find "git not found")
    end)
  end)

  -- ── rev_parse_head ────────────────────────────────────────────

  describe("rev_parse_head", function()
    it("returns trimmed SHA on success", function()
      wez.run_child_process = function()
        return true, "abc123def456\n", ""
      end
      assert.equal("abc123def456", git.rev_parse_head "/repo")
    end)

    it("returns nil on failure", function()
      wez.run_child_process = function()
        return false, "", "fatal: not a git repo"
      end
      assert.is_nil(git.rev_parse_head "/bad")
    end)

    it("returns nil on empty output", function()
      wez.run_child_process = function()
        return true, "", ""
      end
      assert.is_nil(git.rev_parse_head "/empty")
    end)
  end)

  -- ── checkout ──────────────────────────────────────────────────

  describe("checkout", function()
    it("returns true on success", function()
      wez.run_child_process = function()
        return true, "", ""
      end
      local ok, err = git.checkout("/repo", "v1.0")
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("passes ref to git checkout", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      git.checkout("/repo", "feature-branch")
      assert.same({ "git", "-C", "/repo", "checkout", "feature-branch" }, captured_cmd)
    end)

    it("returns false and error on failure", function()
      wez.run_child_process = function()
        return false, "", "error: pathspec 'bad' did not match\n"
      end
      local ok, err = git.checkout("/repo", "bad")
      assert.is_false(ok)
      assert.equal("error: pathspec 'bad' did not match\n", err)
    end)
  end)

  -- ── fetch ─────────────────────────────────────────────────────

  describe("fetch", function()
    it("fetches from origin", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      local ok = git.fetch "/repo"
      assert.is_true(ok)
      assert.same({ "git", "-C", "/repo", "fetch", "origin" }, captured_cmd)
    end)

    it("includes --tags when requested", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      git.fetch("/repo", { tags = true })
      assert.same({ "git", "-C", "/repo", "fetch", "origin", "--tags" }, captured_cmd)
    end)

    it("returns false and error on failure", function()
      wez.run_child_process = function()
        return false, "", "fatal: could not read from remote"
      end
      local ok, err = git.fetch "/repo"
      assert.is_false(ok)
      assert.truthy(err:find "could not read from remote")
    end)
  end)

  -- ── current_branch ────────────────────────────────────────────

  describe("current_branch", function()
    it("returns branch name when on a branch", function()
      wez.run_child_process = function()
        return true, "main\n", ""
      end
      assert.equal("main", git.current_branch "/repo")
    end)

    it("returns nil when HEAD is detached", function()
      wez.run_child_process = function()
        return false, "", "fatal: ref HEAD is not a symbolic ref"
      end
      assert.is_nil(git.current_branch "/repo")
    end)
  end)

  -- ── is_detached ───────────────────────────────────────────────

  describe("is_detached", function()
    it("returns true when detached", function()
      wez.run_child_process = function()
        return false, "", "fatal: ref HEAD is not a symbolic ref"
      end
      assert.is_true(git.is_detached "/repo")
    end)

    it("returns false when on a branch", function()
      wez.run_child_process = function()
        return true, "main\n", ""
      end
      assert.is_false(git.is_detached "/repo")
    end)
  end)

  -- ── merge_ff ──────────────────────────────────────────────────

  describe("merge_ff", function()
    it("merges from origin/HEAD by default", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      local ok = git.merge_ff "/repo"
      assert.is_true(ok)
      assert.same(
        { "git", "-C", "/repo", "merge", "--ff-only", "origin/HEAD" },
        captured_cmd
      )
    end)

    it("merges from specified ref", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      git.merge_ff("/repo", "origin/main")
      assert.same(
        { "git", "-C", "/repo", "merge", "--ff-only", "origin/main" },
        captured_cmd
      )
    end)

    it("returns false on merge conflict", function()
      wez.run_child_process = function()
        return false, "", "fatal: Not possible to fast-forward"
      end
      local ok, err = git.merge_ff "/repo"
      assert.is_false(ok)
      assert.truthy(err:find "Not possible to fast%-forward")
    end)
  end)

  -- ── log_oneline ───────────────────────────────────────────────

  describe("log_oneline", function()
    it("returns parsed log lines", function()
      wez.run_child_process = function()
        return true, "abc1234 first commit\ndef5678 second commit\n", ""
      end
      local lines = git.log_oneline("/repo", "aaa", "bbb")
      assert.same({ "abc1234 first commit", "def5678 second commit" }, lines)
    end)

    it("defaults to_sha to HEAD", function()
      local captured_cmd
      wez.run_child_process = function(cmd)
        captured_cmd = cmd
        return true, "", ""
      end
      git.log_oneline("/repo", "abc123")
      assert.same(
        { "git", "-C", "/repo", "log", "--oneline", "abc123..HEAD" },
        captured_cmd
      )
    end)

    it("returns nil on failure", function()
      wez.run_child_process = function()
        return false, "", "fatal: bad revision"
      end
      assert.is_nil(git.log_oneline("/repo", "bad"))
    end)

    it("returns empty list when no commits in range", function()
      wez.run_child_process = function()
        return true, "", ""
      end
      local lines = git.log_oneline("/repo", "abc", "abc")
      assert.same({}, lines)
    end)
  end)

  -- ── remote_url ────────────────────────────────────────────────

  describe("remote_url", function()
    it("returns trimmed URL", function()
      wez.run_child_process = function()
        return true, "https://github.com/owner/repo\n", ""
      end
      assert.equal("https://github.com/owner/repo", git.remote_url "/repo")
    end)

    it("returns nil on failure", function()
      wez.run_child_process = function()
        return false, "", "fatal: no such remote 'origin'"
      end
      assert.is_nil(git.remote_url "/bad")
    end)
  end)
end)
