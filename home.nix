{
  config,
  pkgs,
  lib,
  minimal-emacs,
  zig,
  paseo,
  herdr,
  herdr-sessionizer,
  herdr-last-workspace,
  ...
}:

let
  # ── Detect user from environment ────────────────────────────────────
  # home-manager switch passes --impure so builtins.getEnv works.
  # Fallbacks are used when evaluating in pure mode (e.g. nix flake check).
  envUser = builtins.getEnv "USER";
  envHome = builtins.getEnv "HOME";

  username = if envUser != "" then envUser else "jay";

  homeDirectory =
    if envHome != "" then
      envHome
    else if pkgs.stdenv.isDarwin then
      "/Users/${username}"
    else
      "/home/${username}";

  # ── Detect work machine ─────────────────────────────────────────────
  # A "work machine" is any host whose /etc/hostname starts with "pairing-".
  # This is the single source of truth for machine-type decisions; branch on
  # `isWorkMachine` anywhere below. The pathExists guard keeps pure-mode eval
  # (e.g. nix flake check) working, mirroring the envUser/envHome fallbacks.
  hostname = if builtins.pathExists /etc/hostname then builtins.readFile /etc/hostname else "";

  isWorkMachine = lib.hasPrefix "pairing-" hostname;

  herdrPackage = herdr.packages.${pkgs.system}.default;
  zigPackage = zig.packages.${pkgs.system}.default;

  herdrLastWorkspacePackage = pkgs.rustPlatform.buildRustPackage {
    pname = "herdr-last-workspace";
    version = "0.1.0";
    src = herdr-last-workspace;
    cargoLock.lockFile = "${herdr-last-workspace}/Cargo.lock";
  };

  herdrWorkspaceManagerPackage = pkgs.rustPlatform.buildRustPackage {
    pname = "herdr-workspace-manager";
    version = "0.6.0-vendored";
    src = ./config/herdr/plugins/workspace-manager;
    cargoLock.lockFile = ./config/herdr/plugins/workspace-manager/Cargo.lock;
  };

  # ── Custom packages not in nixpkgs ──────────────────────────────────

  zjstatus = pkgs.stdenv.mkDerivation rec {
    pname = "zjstatus";
    version = "0.22.0";

    src = pkgs.fetchurl {
      url = "https://github.com/dj95/zjstatus/releases/download/v${version}/zjstatus.wasm";
      hash = "sha256-TeQm0gscv4YScuknrutbSdksF/Diu50XP4W/fwFU3VM=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm644 $src $out/share/zellij/plugins/zjstatus.wasm
      runHook postInstall
    '';

    meta = {
      description = "Configurable statusbar plugin for zellij";
      homepage = "https://github.com/dj95/zjstatus";
      license = lib.licenses.mit;
    };
  };

  # Tree-sitter knowledge-graph code intelligence server for personal hosts.
  codebase-memory-mcp = pkgs.stdenv.mkDerivation rec {
    pname = "codebase-memory-mcp";
    version = "0.8.1";

    src =
      let
        release =
          {
            "x86_64-linux" = {
              asset = "codebase-memory-mcp-linux-amd64-portable.tar.gz";
              hash = "sha256-arh6bAXQSd3ldwCAPKCrQZn88llzoGBmGK8Pzuc/Wr0=";
            };
            "aarch64-linux" = {
              asset = "codebase-memory-mcp-linux-arm64-portable.tar.gz";
              hash = "sha256-E1JqzCpqBpff88dj+0Q6QWWJvBCtixIBW2PYflFd1ys=";
            };
            "aarch64-darwin" = {
              asset = "codebase-memory-mcp-darwin-arm64.tar.gz";
              hash = "sha256-+9BHUJhSAhtURqERQbywo9Hcrr9uURJGCWDynwUsHFg=";
            };
          }
          .${pkgs.stdenv.hostPlatform.system}
            or (throw "codebase-memory-mcp: unsupported system ${pkgs.stdenv.hostPlatform.system}");
      in
      pkgs.fetchurl {
        url = "https://github.com/DeusData/codebase-memory-mcp/releases/download/v${version}/${release.asset}";
        inherit (release) hash;
      };

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 codebase-memory-mcp $out/bin/codebase-memory-mcp
      runHook postInstall
    '';

    meta = {
      description = "Tree-sitter knowledge-graph code intelligence server";
      homepage = "https://github.com/DeusData/codebase-memory-mcp";
      license = lib.licenses.mit;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  };

  # Stable signed/notarized Apple Silicon build from jimeh/emacs-builds.
  jimeh-emacs = pkgs.stdenvNoCC.mkDerivation {
    pname = "jimeh-emacs";
    version = "30.2-1";

    src = pkgs.fetchurl {
      url = "https://github.com/jimeh/emacs-builds/releases/download/Emacs-30.2-1/Emacs.2025-08-14.636f166.emacs-30-2-1.macOS-11.arm64.dmg";
      hash = "sha256-gncCHtPrcWMzEgY4/8JWXBuJPpFG4Gc4uzUhYw856xk=";
    };

    nativeBuildInputs = [ pkgs.undmg ];
    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      cp -R Emacs.app "$out/Applications/Emacs.app"
      for executable in "$out/Applications/Emacs.app/Contents/MacOS/bin/"*; do
        ln -s "$executable" "$out/bin/$(basename "$executable")"
      done
      runHook postInstall
    '';

    meta = {
      description = "Signed and notarized Emacs.app build for macOS";
      homepage = "https://github.com/jimeh/emacs-builds";
      license = lib.licenses.gpl3Plus;
      platforms = [ "aarch64-darwin" ];
    };
  };

in
{

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # ── Packages ────────────────────────────────────────────────────────

  home.packages =
    with pkgs;
    [
      # Shell & terminal
      zellij
      herdrPackage
      bun
      starship
      eza

      # Languages
      nodejs
      pnpm
      python3
      nixd
      nixfmt

      # Utilities
      ripgrep
      cmark
      fzf
      jq
      zoxide
      git-lfs
      postgresql
      gh
      tree
      flock
      ruff
      basedpyright
      drawio

      # Fonts
      fira-code

      # Custom packages
      opener
    ]
    # On Linux use the distro toolchain so it sees distro -dev headers/libs.
    # A Nix-wrapped GCC intentionally cannot see packages installed by apt.
    ++ lib.optionals (!stdenv.isLinux) [
      gcc
    ]
    ++ lib.optionals stdenv.isLinux [
      netcat-openbsd
    ]
    ++ lib.optionals stdenv.isDarwin [
      netcat
    ]
    ++ lib.optionals (stdenv.isLinux && stdenv.hostPlatform.isAarch64) [
      uv
    ]
    ++ lib.optionals stdenv.isLinux [
      emacs-nox
      earlyoom
      inotify-tools
    ]
    # ── Personal-only ─────────────────────────────────────────────────
    # Nothing here is needed on work machines; see `isWorkMachine` above.
    # Keeps roughly 1.6 GiB of closure off work hosts.
    ++ lib.optionals (!isWorkMachine) [
      go
      gopls
      zigPackage
      codebase-memory-mcp
      paseo.packages.${pkgs.system}.paseo # CLI/daemon for headless personal hosts
      python3Packages.grip # markdown preview
      typst
      tinymist # typst LSP
      templ
      difftastic
      forgejo-cli # work uses GitHub Enterprise instead
      ffmpeg # browser automation: `record stop` WebM encoding (pi-agent-browser-native)
    ]
    # Shares ~500 MiB of closure with ffmpeg above, so the two are gated
    # together: dropping only one keeps the shared half alive.
    ++ lib.optionals (stdenv.isLinux && !isWorkMachine) [
      chromium # rendered-UI browser automation (agent-browser / pi-browser-use)
    ]
    ++ lib.optionals stdenv.isDarwin [
      fswatch
      ghostty-bin
      jimeh-emacs
    ];

  # ── Environment variables ───────────────────────────────────────────

  home.sessionVariables = {
    COLORTERM = "truecolor";
    EDITOR = "emacsclient -t -a emacs";
    VISUAL = "emacsclient -t -a emacs";
    GOPATH = "$HOME/go";
    GOBIN = "$HOME/go/bin";
    PNPM_HOME = "$HOME/.local/share/pnpm";
  }
  // lib.optionalAttrs (pkgs.stdenv.isLinux && !isWorkMachine) {
    # Browser automation uses Nix Chromium only where Chromium is installed.
    AGENT_BROWSER_EXECUTABLE_PATH = "$HOME/bin/chromium-nosandbox";
  }
  // lib.optionalAttrs (!isWorkMachine) {
    CBM_MCP_BIN = "$HOME/.nix-profile/bin/codebase-memory-mcp";
  };

  home.sessionPath = [
    "$HOME/bin"
    "$HOME/.local/bin"
    "$HOME/go/bin"
    "$HOME/.local/share/pnpm" # nix-managed pnpm globals (pi, agent-browser, ...)
    "$HOME/.npm-global/bin" # legacy npm-global CLIs (pi-installed package bins)
  ]
  # Hand-installed Racket lives on personal hosts only. Unlike fish_add_path,
  # sessionPath does not skip missing directories, so gate it explicitly.
  ++ lib.optionals (!isWorkMachine) [
    "$HOME/racket/bin"
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [
    "${jimeh-emacs}/Applications/Emacs.app/Contents/MacOS/bin"
  ];

  # ── Fish shell ──────────────────────────────────────────────────────
  # home-manager generates its own config.fish (with session vars, etc.),
  # so we source our custom config from interactiveShellInit instead of
  # symlinking config.fish directly.

  programs.fish = {
    enable = true;
    # Nix puts ~/.nix-profile/bin on PATH from /etc/profile.d/nix.sh, which
    # only POSIX login shells read. Since install.sh started chsh-ing fish to
    # be the login shell, nothing sourced it anymore and the entire nix
    # profile (starship, zoxide, herdr, ...) fell off PATH. Nix ships a fish
    # port of that script; source it, and do it from shellInit so PATH is
    # right before interactiveShellInit runs `starship init fish`.
    shellInit = ''
      if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
          source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
      end
    '';
    interactiveShellInit = builtins.readFile ./config/fish/config.fish;
  };

  programs.bash.enable = true;

  programs.starship = {
    enable = true;
    enableFishIntegration = false; # we call `starship init fish | source` in config.fish
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = false; # we call `zoxide init` in config.fish
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = false; # we use PatrickF1/fzf.fish plugin instead
  };

  # Symlink fish support files (functions only — fish_plugins is left
  # unmanaged so Fisher can write to it after plugin installs).
  # Out-of-store symlinks so edits take effect without `home-manager switch`.
  xdg.configFile = {
    "fish/functions/fisher.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/fisher.fish";
      force = true;
    };
    "fish/functions/zlast.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/zlast.fish";
      force = true;
    };
    "fish/functions/ws.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/ws.fish";
      force = true;
    };
    "fish/functions/athenaq.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/athenaq.fish";
      force = true;
    };
  };

  # Seed fish_plugins on first run only (Fisher owns it after that)
  home.activation.seedFishPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.config/fish/fish_plugins" ]; then
      run mkdir -p "$HOME/.config/fish"
      run cp "${./config/fish/fish_plugins}" "$HOME/.config/fish/fish_plugins"
      run chmod 644 "$HOME/.config/fish/fish_plugins"
    fi
  '';

  # ── Git ─────────────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    lfs.enable = true;

    settings = {
      # No global email on work machines: identity there comes entirely from
      # the untracked ~/.config/git/local (see includes below), which keeps
      # work addresses out of this repo. git ignores a missing include path
      # without any warning, so useConfigOnly supplies the missing noise --
      # it disables the username@hostname guess, which otherwise commits
      # silently as ubuntu@pairing-<host>.nonprod.internal and puts an
      # internal hostname in commits that may get pushed somewhere public.
      user = {
        name = "Jay Bonthius";
        useConfigOnly = true;
      }
      // lib.optionalAttrs (!isWorkMachine) {
        email = "jaybonthius@gmail.com";
      };
      init.defaultBranch = "main";
      # These shell out to `difft`, which is personal-only (see the
      # isWorkMachine package gate above). Defining them where difftastic
      # is absent just yields "cannot run difft" at diff time.
      alias = lib.optionalAttrs (!isWorkMachine) {
        dft = "-c diff.external=difft diff";
        ds = "-c diff.external=difft show --ext-diff";
        dl = "-c diff.external=difft log -p --ext-diff";
      };
    };

    includes = [
      # Deliberately unmanaged and untracked: the escape hatch for identities
      # that must not land in a public repo (work email, employer host
      # patterns). Written by hand per machine. Listed first so the
      # conditional includes below still win where they match.
      {
        path = "~/.config/git/local";
      }
      {
        condition = "gitdir:~/Code/engineering-resume/";
        path = "~/.config/git/codeberg";
      }
      {
        condition = "hasconfig:remote.*.url:ssh://gitea@git.cons.io:2222/**";
        path = "~/.config/git/git-cons";
      }
    ];
  };

  # Conditional Git identity configs (raw files, referenced by includes above)
  xdg.configFile."git/codeberg" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/git/codeberg";
    force = true;
  };

  xdg.configFile."git/git-cons" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/git/git-cons";
    force = true;
  };

  # ── Emacs ───────────────────────────────────────────────────────────
  # Emacs config uses Elpaca for package management, so we just symlink
  # the config files. minimal-emacs.d is a flake input.
  #
  # Local files use mkOutOfStoreSymlink so edits take effect on Emacs
  # restart without needing `home-manager switch`.

  xdg.configFile."emacs/early-init.el" = {
    source = "${minimal-emacs}/early-init.el";
    force = true;
  };
  xdg.configFile."emacs/init.el" = {
    source = "${minimal-emacs}/init.el";
    force = true;
  };
  xdg.configFile."emacs/pre-early-init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/emacs/pre-early-init.el";
    force = true;
  };
  xdg.configFile."emacs/pre-init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/emacs/pre-init.el";
    force = true;
  };
  xdg.configFile."emacs/post-init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/emacs/post-init.el";
    force = true;
  };
  # ── Claude Code ─────────────────────────────────────────────────────
  # Base config (personal/non-work settings). Merged with
  # settings.local.json (work plugins, gitignored) at activation time
  # to produce the final ~/.claude/settings.json.

  home.file.".claude/settings.base.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/claude/settings.base.json";
    force = true;
  };

  # ── Pi Coding Agent (personal machines only) ─────────────────────────
  # Existing Pi state on pairing hosts is intentionally left unmanaged.
  home.file.".pi/agent/settings.base.json" = lib.mkIf (!isWorkMachine) {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/settings.base.json";
    force = true;
  };

  home.file.".pi/agent/extensions" = lib.mkIf (!isWorkMachine) {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/extensions";
    force = true;
  };

  home.file.".pi/agent/AGENTS.md" = lib.mkIf (!isWorkMachine) {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/AGENTS.md";
    force = true;
  };

  home.file.".pi/agent/APPEND_SYSTEM.md" = lib.mkIf (!isWorkMachine) {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/APPEND_SYSTEM.md";
    force = true;
  };

  home.file.".agents/skills/codebase-memory-cli" = lib.mkIf (!isWorkMachine) {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/codebase-memory-cli";
    force = true;
  };

  home.file.".agents/skills/actual-categorize" = lib.mkIf (!isWorkMachine) {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/actual-categorize";
    force = true;
  };

  home.file.".agents/skills/drawio-skill" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/drawio-skill";
    force = true;
  };

  # Shared workflow skills extracted from project-local Pi skills.
  # Project-local skills retain precedence until each repository is reviewed
  # and migrated separately.
  home.file.".agents/skills/code-review" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/code-review";
    force = true;
  };

  home.file.".agents/skills/develop" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/develop";
    force = true;
  };

  home.file.".agents/skills/diagnosing-bugs" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/diagnosing-bugs";
    force = true;
  };

  home.file.".agents/skills/grilling" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/grilling";
    force = true;
  };

  home.file.".agents/skills/handoff" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/handoff";
    force = true;
  };

  home.file.".agents/skills/implement" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/implement";
    force = true;
  };

  home.file.".agents/skills/research" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/research";
    force = true;
  };

  home.file.".agents/skills/tdd" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/tdd";
    force = true;
  };

  home.file.".agents/skills/domain-modeling" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/domain-modeling";
    force = true;
  };

  home.file.".agents/skills/codebase-design" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/codebase-design";
    force = true;
  };

  home.file.".agents/skills/to-spec" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/to-spec";
    force = true;
  };

  home.file.".agents/skills/to-tickets" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/to-tickets";
    force = true;
  };

  home.file.".agents/skills/save-discoveries" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/save-discoveries";
    force = true;
  };

  # ── Piscord (Discord gateway daemon) ────────────────────────────────
  # The `pi-discord-gateway` systemd *user* service is generated by
  # `piscord daemon install`, and systemd user services run with a minimal
  # PATH (/usr/bin:/bin). This drop-in gives the daemon a real PATH so it can
  # find `pi` (pnpm global) and `node` (nix profile) when it shells out to the
  # agent, and points pi at the bot-only config dir (PI_CODING_AGENT_DIR) so the
  # Discord bot loads every extension EXCEPT pi-codebase-memory-mcp -- whose
  # long-lived codebase-memory-mcp server child otherwise keeps headless pi
  # alive forever (see genPiDiscordConfig below). Drop-ins survive piscord
  # regenerating the main unit; `%h` = $HOME.
  xdg.configFile."systemd/user/pi-discord-gateway.service.d/override.conf" =
    lib.mkIf (pkgs.stdenv.isLinux && !isWorkMachine)
      {
        text = ''
          [Service]
          Environment=PATH=%h/.local/share/pnpm:%h/.npm-global/bin:%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin
          Environment=PI_CODING_AGENT_DIR=%h/.pi/discord-agent
          ExecStart=
          ExecStart=%h/.local/share/pnpm/piscord start
        '';
      };

  # ── Herdr ───────────────────────────────────────────────────────────

  xdg.configFile."herdr/config.toml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/herdr/config.toml";
    force = true;
  };

  xdg.configFile."herdr/plugins/config/sessionizer/config.toml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/herdr/${
      if isWorkMachine then "sessionizer-work" else "sessionizer-personal"
    }.toml";
    force = true;
  };

  xdg.configFile."herdr/plugins/config/herdr-plugin-workspace-manager/config.yml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/herdr/${
      if isWorkMachine then "workspace-manager-work" else "workspace-manager-personal"
    }.yml";
    force = true;
  };

  # ── Zellij ──────────────────────────────────────────────────────────

  xdg.configFile."zellij/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/config.kdl";
    force = true;
  };

  # Deployed per-file (not whole-dir) so the machine-appropriate project
  # layout can be selected: work machines get claude, everything else pi.
  # The deployed filename stays project.kdl so LAYOUT="project" (in
  # zellij-session-open) and default_layout "project" keep working.
  xdg.configFile."zellij/layouts/project.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/layouts/${
      if isWorkMachine then "work" else "personal"
    }-layout.kdl";
    force = true;
  };

  xdg.configFile."zellij/layouts/copilot.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/layouts/copilot.kdl";
    force = true;
  };

  # Zellij plugins (from derivations)
  xdg.configFile."zellij/plugins/zjstatus.wasm" = {
    source = "${zjstatus}/share/zellij/plugins/zjstatus.wasm";
    force = true;
  };

  # ── User scripts (~/bin/) ───────────────────────────────────────────

  home.file."bin/opener-open" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/bin/opener-open";
    force = true;
  };

  home.file."bin/emacs-open-context" = {
    source = ./config/bin/emacs-open-context;
    executable = true;
    force = true;
  };

  home.file."bin/agent-open-context" = {
    source = ./config/bin/agent-open-context;
    executable = true;
    force = true;
  };

  # Chromium --no-sandbox wrapper for agent browser automation.
  # Personal-only: the Chromium it wraps is gated the same way.
  home.file."bin/chromium-nosandbox" = lib.mkIf (pkgs.stdenv.isLinux && !isWorkMachine) {
    source = ./config/bin/chromium-nosandbox;
    executable = true;
    force = true;
  };

  home.file."bin/zellij-session-open" = {
    source = ./config/bin/zellij-session-open;
    executable = true;
    force = true;
  };

  home.file."bin/zellij-sessionizer" = {
    source = ./config/bin/zellij-sessionizer;
    executable = true;
    force = true;
  };

  home.file."bin/zellij-session-name" = {
    source = ./config/bin/zellij-session-name;
    executable = true;
    force = true;
  };

  home.file."bin/theme-state-to-gsettings" = lib.mkIf pkgs.stdenv.isLinux {
    source = ./config/bin/theme-state-to-gsettings;
    executable = true;
    force = true;
  };

  home.file."bin/git-sync-main-master" = {
    source = ./config/bin/git-sync-main-master;
    executable = true;
    force = true;
  };

  # ── Systemd user services (Linux only) ──────────────────────────────

  systemd.user.services = lib.mkIf pkgs.stdenv.isLinux {

    emacs-daemon = {
      Unit = {
        Description = "Emacs daemon";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.emacs-nox}/bin/emacs --fg-daemon";
        Restart = "on-failure";
        RestartSec = "3s";
        Environment = [
          "PATH=%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:%h/bin:%h/.local/bin:${
            lib.optionalString (!isWorkMachine) "%h/racket/bin:"
          }%h/go/bin:/opt/gerbil/bin:/usr/local/bin:/usr/bin:/bin"
          "SSH_AUTH_SOCK=%h/.ssh/ssh_auth_sock"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    theme-state-to-gsettings = {
      Unit = {
        Description = "Sync ~/.local/state/theme to GNOME";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "%h/bin/theme-state-to-gsettings";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };

  systemd.user.paths = lib.mkIf pkgs.stdenv.isLinux {
    theme-state-to-gsettings = {
      Unit = {
        Description = "Watch ~/.local/state/theme and sync GNOME appearance";
      };
      Path = {
        PathChanged = [
          "%h/.local/state/theme"
          "%h/.local/state"
        ];
        Unit = "theme-state-to-gsettings.service";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };

  # ── Launchd agents (macOS only) ─────────────────────────────────────

  launchd.agents.emacs-daemon = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${jimeh-emacs}/Applications/Emacs.app/Contents/MacOS/Emacs"
        "--fg-daemon"
      ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  # ── Terminfo (activation script) ────────────────────────────────────

  home.activation.compileTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "${./config/terminfo/xterm-ghostty.ti}" ]; then
      run ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" "${./config/terminfo/xterm-ghostty.ti}"
    fi
  '';

  # ── Claude Code config merge (activation scripts) ──────────────────
  # settings.base.json   — Nix-managed personal plugins (home.file above)
  # settings.local.json  — work plugins / Cox-specific (gitignored)
  # settings.json        — deep-merged result, rewritten every activation

  # Seed settings.local.json once from the existing settings.json's
  # work-specific keys (genai-enablement plugins + extraKnownMarketplaces).
  # After seeding, the file is left alone so the user can edit it freely.
  home.activation.seedClaudeLocal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    local="$HOME/.claude/settings.local.json"
    current="$HOME/.claude/settings.json"
    if [ ! -f "$local" ] && [ -f "$current" ]; then
      run mkdir -p "$HOME/.claude"
      # Extract work-specific plugins and marketplaces
      run ${pkgs.jq}/bin/jq '{
        enabledPlugins: (.enabledPlugins // {} | with_entries(select(.key | endswith("@genai-enablement")))),
        extraKnownMarketplaces: (.extraKnownMarketplaces // {})
      }' "$current" > "$local"
    fi
  '';

  # Install pnpm global packages (deep merge, OpenSpec, pi-coding-agent, skills,
  # the upstream agent-browser CLI that pi-agent-browser-native drives, and
  # piscord -- a Discord gateway daemon that shells out to `pi`).
  # PATH must include nodejs/bin so postinstall scripts can find `node`,
  # and PNPM_HOME must be on PATH for pnpm to accept global installs.
  # Do not let pnpm's optional self-managed Node/npm live under $PNPM_HOME:
  # pnpm-generated CLI shims prefer $PNPM_HOME/node over PATH, and old npm/npx
  # shims point at $PNPM_HOME/nodejs/<old>/... directly. Both can make native
  # deps (e.g. piscord -> better-sqlite3) or pi package installs run under or
  # search for an older Node than the Nix Node that built them after upgrades.
  #
  # agent-browser is pinned: pi-agent-browser-native enforces an EXACT upstream
  # version via `pi-agent-browser-doctor`. When that doctor reports drift, bump
  # the pin here to the version it expects, then re-run `home-manager switch`.
  #
  # --allow-build whitelists native postinstall builds (pnpm v10 blocks them by
  # default). piscord needs better-sqlite3 to fetch/compile its native binding.
  #
  # NOTE (known, intentionally deferred): `pi` and `openspec` ALSO exist as
  # hand-installed copies under ~/.npm-global/bin, which is earlier on PATH and
  # shadows these nix-managed pnpm copies. Harmless today (same versions) but not
  # reproducible. Revisit by removing the ~/.npm-global duplicates so the
  # nix-managed copies win, and auditing the other ~/.npm-global CLIs
  # (pi-browser-use, pi-subagents, pi-mcp-adapter, taskplane, latchkey,
  # claude-agent-acp) for pi-managed vs. orphaned.
  home.activation.installPnpmGlobals = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    run mkdir -p "$PNPM_HOME"
    run rm -f "$PNPM_HOME/node" "$PNPM_HOME/npm" "$PNPM_HOME/npx"
    run rm -rf "$PNPM_HOME/nodejs"
    PATH="${pkgs.nodejs}/bin:$PNPM_HOME:$PATH" \
      run ${pkgs.pnpm}/bin/pnpm add -g --allow-build=better-sqlite3 \
        deepmerge @fission-ai/openspec@latest skills ${
          lib.optionalString (!isWorkMachine) "@earendil-works/pi-coding-agent agent-browser@0.33.2 piscord"
        }
  '';

  # Install Caveman for Claude Code everywhere and additionally for Pi on
  # personal machines.
  home.activation.installCavemanSkill =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "installPnpmGlobals"
      ]
      ''
        export PNPM_HOME="$HOME/.local/share/pnpm"
        PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:$PNPM_HOME:$PATH"

        run ${pkgs.nodejs}/bin/npx -y skills add JuliusBrussee/caveman -g \
          -a claude-code ${lib.optionalString (!isWorkMachine) "pi"} -y
      '';

  # Install the reviewed Archify release globally for Pi. Pin the release so a
  # Home Manager switch cannot silently replace the executable skill contents.
  home.activation.installArchifySkill = lib.mkIf (!isWorkMachine) (
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "installPnpmGlobals"
      ]
      ''
        export PNPM_HOME="$HOME/.local/share/pnpm"
        PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:$PNPM_HOME:$PATH"

        run ${pkgs.nodejs}/bin/npx -y skills add tt-a1i/archify@v2.13.0 -g -a pi -s archify --copy -y
      ''
  );

  home.activation.installHerdrSessionizer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="${pkgs.bun}/bin:${pkgs.git}/bin:${herdrPackage}/bin:$PATH"
    source_dir=${herdr-sessionizer}
    target_dir="$HOME/.local/share/herdr/plugins-src/sessionizer"
    marker="$target_dir/.nix-source"

    if [[ ! -f "$marker" ]] || [[ "$(cat "$marker")" != "$source_dir" ]]; then
      rm -rf "$target_dir"
      mkdir -p "$target_dir"
      cp -R "$source_dir"/. "$target_dir"/
      chmod -R u+w "$target_dir"
      cd "$target_dir"
      ${pkgs.bun}/bin/bun install --frozen-lockfile
      ${herdrPackage}/bin/herdr plugin unlink sessionizer >/dev/null 2>&1 || true
      ${herdrPackage}/bin/herdr plugin link "$target_dir"
      printf '%s\n' "$source_dir" > "$marker"
    fi
  '';

  home.activation.installHerdrLastWorkspace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    source_dir=${herdr-last-workspace}
    target_dir="$HOME/.local/share/herdr/plugins-src/last-workspace"
    marker="$target_dir/.nix-source"

    if [[ ! -f "$marker" ]] || [[ "$(cat "$marker")" != "$source_dir" ]]; then
      rm -rf "$target_dir"
      mkdir -p "$target_dir/target/release"
      cp -R "$source_dir"/. "$target_dir"/
      chmod -R u+w "$target_dir"
      install -Dm755 ${herdrLastWorkspacePackage}/bin/herdr-last-workspace \
        "$target_dir/target/release/herdr-last-workspace"
      ${herdrPackage}/bin/herdr plugin unlink third774.last-workspace >/dev/null 2>&1 || true
      ${herdrPackage}/bin/herdr plugin link "$target_dir"
      printf '%s\n' "$source_dir" > "$marker"
    fi
  '';

  home.activation.installHerdrWorkspaceManager = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    source_dir=${./config/herdr/plugins/workspace-manager}
    target_dir="$HOME/.local/share/herdr/plugins-src/workspace-manager"
    marker="$target_dir/.nix-source"

    if [[ ! -f "$marker" ]] || [[ "$(cat "$marker")" != "$source_dir" ]]; then
      rm -rf "$target_dir"
      mkdir -p "$target_dir/target/release"
      cp -R "$source_dir"/. "$target_dir"/
      chmod -R u+w "$target_dir"
      install -Dm755 ${herdrWorkspaceManagerPackage}/bin/herdr-workspace-manager \
        "$target_dir/target/release/herdr-workspace-manager"
      ${herdrPackage}/bin/herdr plugin unlink herdr-plugin-workspace-manager >/dev/null 2>&1 || true
      ${herdrPackage}/bin/herdr plugin link "$target_dir"
      printf '%s\n' "$source_dir" > "$marker"
    fi
  '';

  # ── Pi Coding Agent config merge (activation scripts) ───────────────
  # settings.base.json  — Nix-managed settings + packages (home.file above)
  # settings.local.json — machine-specific overrides (gitignored)
  # settings.json       — deep-merged result, rewritten every activation

  # Seed settings.local.json once from the existing settings.json's
  # non-base keys. After seeding, the file is left alone so the user
  # can edit it freely.
  home.activation.seedPiLocal = lib.mkIf (!isWorkMachine) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      local="$HOME/.pi/agent/settings.local.json"
      current="$HOME/.pi/agent/settings.json"
      if [ ! -f "$local" ] && [ -f "$current" ]; then
        run mkdir -p "$HOME/.pi/agent"
        # Extract keys that are NOT in the base config
        run ${pkgs.jq}/bin/jq '{
          lastChangelogVersion: .lastChangelogVersion
        } | with_entries(select(.value != null))' "$current" > "$local"
      fi
    ''
  );

  # Merge base + local into settings.json on every activation.
  home.activation.mergePiConfig = lib.mkIf (!isWorkMachine) (
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "seedPiLocal"
        "installPnpmGlobals"
      ]
      ''
        base="$HOME/.pi/agent/settings.base.json"
        local="$HOME/.pi/agent/settings.local.json"
        target="$HOME/.pi/agent/settings.json"

        run mkdir -p "$HOME/.pi/agent"
        if [ -f "$local" ]; then
          run ${pkgs.nodejs}/bin/node -e "
            const m = require('$HOME/.local/share/pnpm/global/5/node_modules/deepmerge');
            const fs = require('fs');
            const a = JSON.parse(fs.readFileSync('$base'));
            const b = JSON.parse(fs.readFileSync('$local'));
            console.log(JSON.stringify(m(a, b), null, 2));
          " > "$target"
        else
          run cp "$base" "$target"
        fi
      ''
  );

  # Bot-only pi config dir for piscord (the Discord gateway). Mirrors the
  # interactive ~/.pi/agent/settings.json but drops pi-codebase-memory-mcp,
  # whose long-lived codebase-memory-mcp server child keeps pi alive and made
  # headless (--print) runs hang. Every other extension stays. pi auto-installs
  # the trimmed package set into ~/.pi/discord-agent/npm on first run, and
  # auth.json is symlinked so the bot reuses the interactive login. The piscord
  # systemd unit points pi here via PI_CODING_AGENT_DIR (drop-in above).
  home.activation.genPiDiscordConfig = lib.mkIf (pkgs.stdenv.isLinux && !isWorkMachine) (
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "mergePiConfig"
      ]
      ''
        botdir="$HOME/.pi/discord-agent"
        run mkdir -p "$botdir"
        run ${pkgs.jq}/bin/jq '.packages |= map(select(. != "npm:pi-codebase-memory-mcp"))' \
          "$HOME/.pi/agent/settings.json" > "$botdir/settings.json"
        run ln -sf "$HOME/.pi/agent/auth.json" "$botdir/auth.json"
      ''
  );

  # Local-only patch for pi-agent-browser-native 0.2.61. Its short runtime
  # prompt over-compresses the fuller docs from "respect explicit user stop
  # boundaries" into an unconditional "Stop before order/post/purchase/submit",
  # which prevents explicitly requested send/submit browser flows. Patch the
  # installed package copies after Pi package install/config generation so the
  # fix survives Home Manager switches and Pi package reinstalls.
  home.activation.patchPiAgentBrowserNativePrompt = lib.mkIf (!isWorkMachine) (
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "installPnpmGlobals"
        "genPiDiscordConfig"
      ]
      ''
        old='For agent_browser, use open → snapshot -i → current @refs or semanticAction → re-snapshot after navigation/scroll/rerender. Batch same-snapshot forms; split before navigation/submits. Stop before order/post/purchase/submit.'
        new='For agent_browser, use open → snapshot -i → current @refs or semanticAction → re-snapshot after navigation/scroll/rerender. Batch same-snapshot forms; split before navigation/submits. Respect explicit user stop boundaries: if the user asks to stop before order/post/purchase/submit, stop there; otherwise complete explicitly requested submit/send actions after verifying the target.'

        for f in \
          "$HOME/.pi/agent/npm/node_modules/pi-agent-browser-native/dist/extensions/agent-browser/lib/playbook.js" \
          "$HOME/.pi/discord-agent/npm/node_modules/pi-agent-browser-native/dist/extensions/agent-browser/lib/playbook.js"
        do
          if [ -f "$f" ] && grep -Fq "$old" "$f"; then
            run ${pkgs.python3}/bin/python3 -c 'import sys; p,o,n=sys.argv[1:]; s=open(p,encoding="utf-8").read(); open(p,"w",encoding="utf-8").write(s.replace(o,n) if o in s else s)' "$f" "$old" "$new"
          fi
        done
      ''
  );

  # Merge base + local into settings.json on every activation.
  # Uses deepmerge-cli for proper recursive merge with array union.
  home.activation.mergeClaudeConfig =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "seedClaudeLocal"
        "installPnpmGlobals"
      ]
      ''
        base="$HOME/.claude/settings.base.json"
        local="$HOME/.claude/settings.local.json"
        target="$HOME/.claude/settings.json"

        run mkdir -p "$HOME/.claude"
        if [ -f "$local" ]; then
          run ${pkgs.nodejs}/bin/node -e "
            const m = require('$HOME/.local/share/pnpm/global/5/node_modules/deepmerge');
            const fs = require('fs');
            const a = JSON.parse(fs.readFileSync('$base'));
            const b = JSON.parse(fs.readFileSync('$local'));
            console.log(JSON.stringify(m(a, b), null, 2));
          " > "$target"
        else
          run cp "$base" "$target"
        fi
      '';

}
