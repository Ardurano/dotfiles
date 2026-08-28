# Migrating an existing Mac into this config

This repo was adopted onto a Mac that already had a hand-installed Homebrew with
33 formulae and 4 casks on it. Because `homebrew.onActivation.cleanup = "zap"`
uninstalls anything not declared in `configuration.nix`, adopting it in one step
would have removed almost all of that. The migration is therefore split into
staged switches.

**Switches 1 and 2 are applied.** Switch 3 is the checklist at the bottom.

## Ownership split

Every tool has exactly one owner. Nothing is installed twice, so nothing is
ambiguous on `PATH`.

| Owner | What | Why |
| --- | --- | --- |
| Nix (`home.nix`) | CLI tools, fonts | Pinned by `flake.lock`, reproducible |
| Homebrew (`configuration.nix`) | GUI casks + 3 CLI tools | Not servable from nixpkgs on darwin |

What cannot move to Nix, and why:

- `ghostty` - nixpkgs sets `meta.platforms = lib.platforms.linux`; there is no
  darwin build at all.
- `wezterm` - nixpkgs builds on darwin, but the cask is what installs
  `/Applications/WezTerm.app` so Spotlight, Dock and Launchpad find it.
- `herdr` - not packaged in nixpkgs.
- `copilot-cli` - not packaged in nixpkgs.
- `opensuperwhisper` - third-party tap (`my-monkeys/tap`) only.
- `ollama` - runs as a brew-managed LaunchAgent (`brew services`). The Nix
  package installs fine, but nothing recreates the auto-start, so moving it
  would silently stop the daemon from launching at login.
- `pyenv` - nixpkgs pins 2.6.31 on **both** the stable and unstable channels
  against 2.8.4 in Homebrew. pyenv's version determines which Python releases
  `python-build` knows how to compile, and a Nix copy cannot self-update.
- `jenv` - not packaged in nixpkgs on either channel.
- `corretto@21`, `corretto@25` - `pkgs.corretto21` and `pkgs.corretto25` exist
  but set `meta.platforms` to Linux only, so they evaluate to
  `meta.available = false` on `aarch64-darwin`; nixpkgs cannot serve a Corretto
  JDK on macOS at all. The casks also install their `.pkg` into
  `/Library/Java/JavaVirtualMachines`, which is where `/usr/libexec/java_home`,
  IntelliJ and the rest of the team look for a JDK. Both are pinned to a major
  version rather than the unversioned `corretto` cask, which would drift to 26
  on release and silently change what `jenv` resolves.

### Two nixpkgs channels

`nixpkgs-26.05-darwin` is a stable *release* branch: it takes security
backports, not version bumps. Measured against Homebrew at migration time, most
tools were within a patch or two, but `glow` was a major version behind and
`uv`, `gemini-cli` and `neovim` were meaningfully stale - and updating
`flake.lock` did not help, because the branch itself is frozen until 26.11.

`flake.nix` therefore carries a second `nixpkgs-unstable` input, exposed by an
overlay in `configuration.nix` as `pkgs.unstable.<name>`. Only the tools that
need it are pulled from there. Both channels are pinned in `flake.lock`, so
reproducibility is unaffected.

Before adding a package to `pkgs.unstable`, check that it actually helps -
`pandoc` is 3.7.0.2 on both channels, so it stays on stable.

`claude` is deliberately **not** declared. It is the native self-updating
installer at `~/.local/share/claude/versions/`; adding the `claude-code` cask
would install a competing second copy.

## Switch 1 (done)

- `nix-homebrew.autoMigrate = true` so activation adopts the pre-existing
  `/opt/homebrew` instead of aborting on a prefix it does not own.
- Every formula and cask that was already installed is declared, so `zap`
  removes nothing.
- `home-manager.backupFileExtension = "hm-bak"` so a file already sitting where
  Home Manager wants to write gets renamed rather than failing the switch.
- Live configs moved into `home/` and symlinked back out: nvim, ghostty,
  `.claude/settings.json`, `AGENTS.md`.
- `programs.zsh.enable = false` - see below.

Three orphaned Homebrew dependencies were intentionally **not** declared and get
garbage-collected on the first switch: `icu4c@77` (superseded by `icu4c@78`),
`unbound`, and `libevent` (only ever used by `unbound`). None were installed on
request and nothing depends on them. Restore with
`brew install icu4c@77 unbound` if that turns out to be wrong.

`docker-completion` was in the same state; it was marked installed-on-request
(`brew install docker-completion`) so that `brew autoremove` leaves it alone.

Loose ends the first switch created, all since resolved:

- `starship` had been hand-installed at `/usr/local/bin/starship`, outside both
  package managers. `programs.starship.enable` makes Nix own it; the old binary
  was deleted. Note that removing a binary out from under a running zsh leaves a
  stale entry in its command hash - `rehash` fixes that shell.
- `programs.starship` writes `~/.config/starship.toml`, which did not exist
  before, so the prompt took on this repo's format. Revert by setting
  `programs.starship.enable = false`.
- 96 JetBrainsMono Nerd Font files had been hand-dropped into `~/Library/Fonts`.
  Nix ships byte-for-byte identical files (Nerd Fonts 3.4.0) into
  `~/Library/Fonts/HomeManager`, which macOS does scan - subdirectories of the
  font directories are traversed. Keeping both registered every face twice, so
  the originals were deleted. The trade is that the fonts now exist only while
  `nerd-fonts.jetbrains-mono` stays in `home.packages`; a later switch that
  drops it will `rsync --delete` them away.

## Switch 2 (done): CLI tools moved to Nix

`homebrew.brews` went from 30 entries to 3. `zap` performed the Homebrew
uninstall in the same activation that installed the Nix replacements, so there
was no window where a tool was missing.

| Homebrew | nixpkgs |
| --- | --- |
| `colima` | `colima` |
| `coreutils` | `coreutils` |
| `docker` | `docker-client` (client only; colima provides the engine) |
| `docker-buildx` | `docker-buildx` |
| `docker-completion` | drop - the Nix client ships its own completions |
| `docker-compose` | `docker-compose` |
| `docker-credential-helper` | `docker-credential-helpers` |
| `findutils` | `findutils` |
| `fzf` | `fzf` |
| `gemini-cli` | `gemini-cli` |
| `gh` | `gh` |
| `git` | `git` |
| `glow` | `glow` |
| `gnupg` | `gnupg` + `pinentry_mac` |
| `go` | `go` |
| `hl` | `hl-log-viewer` |
| `lua@5.4` | `lua5_4` |
| `luarocks` | `luarocks` |
| `maven` | `maven` |
| `neovim` | `pkgs.unstable.neovim` - 0.12.x is required, `init.lua` uses `vim.pack`. 26.05 is pinned at 0.12.3, unstable tracks 0.12.4. |
| `ollama` | **stays on Homebrew** - LaunchAgent, see above |
| `pandoc` | `pandoc` - 3.7.0.2 on both channels vs 3.10.2 in Homebrew, but the lag is cosmetic |
| `pipenv` | `pipenv` |
| `pyenv` | **stays on Homebrew** - see above |
| `ripgrep` | `ripgrep` |
| `tree` | `tree` |
| `tree-sitter-cli` | `tree-sitter` |
| `uv` | `pkgs.unstable.uv` - uv ships constantly; 26.05 is 0.11.x |
| `zsh-vi-mode` | **dropped** - installed but referenced nowhere; `~/.zshrc` loads oh-my-zsh's own `vi-mode` plugin instead |

`nix build .#darwinConfigurations.mac.system --no-link` validates every attribute
name before anything is applied.

### `~/.zshrc` lines removed during Switch 2

```sh
export FZF_BASE=/opt/homebrew/Cellar/fzf/0.66.0
export PATH="$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
export MANPATH="$HOMEBREW_PREFIX/opt/coreutils/libexec/gnuman:$MANPATH"
```

Nix `coreutils` and `findutils` install unprefixed GNU binaries and their man
pages straight into `/etc/profiles/per-user/$USER`, which already sits ahead of
`/usr/bin` on `PATH`, so the `gnubin`/`gnuman` lines have nothing to point at.
`FZF_BASE` hardcoded a Cellar version path that stops existing; oh-my-zsh's
`fzf` plugin does not need it, because its first strategy is
`eval "$(fzf --zsh)"` for any fzf >= 0.48.

### Commands that disappeared, and why that is fine

Removing 30 formulae also removed 93 of their transitive dependencies, taking
387 binaries with them. Almost all were internal library tools nothing invoked
(`tiff*`, `webp*`, `jpeg*`, `msg*`, `icu*`, `libpng-config`, and so on). The
ones worth naming:

- `node` / `npm` / `npx` arrived as a Homebrew dependency of `gemini-cli`. The
  Nix `gemini-cli` bundles node internally without exposing it, so `nodejs` is
  now declared explicitly in `home.packages`. Homebrew had node 26.x (current
  line); nixpkgs ships 24.x LTS.
- `java`, `javac`, `keytool` and friends came from `openjdk`, a `maven`
  dependency. Homebrew keeps `openjdk` keg-only, so none of them were on `PATH`
  anyway - `java` resolves to `/usr/bin/java`, which points at a hand-installed
  GraalVM 21 in `~/Library/Java`. Unaffected.
- The `g`-prefixed coreutils (`gls`, `gdate`, `gcp`, ...) are gone. Nix
  `coreutils` installs the unprefixed GNU binaries directly, which is what the
  old `gnubin` `PATH` entry was providing. Add `coreutils-prefixed` if the `g`
  names are ever wanted.
- `lima` / `limactl` were a `colima` dependency. Nix `colima` bundles lima
  internally, so `colima` itself works, but `limactl` is no longer on `PATH`.
  Add `lima` to `home.packages` if you drive the VM directly.

### PATH ordering to be aware of

`~/.cargo/bin` sits **ahead** of the Nix profile. A cargo-installed
`tree-sitter` therefore shadows the Nix one. `cargo uninstall tree-sitter-cli`
if Nix should own it. The same applies to anything else installed with
`cargo install`.

### Verify after Switch 2

- **`mvn` changed JDK.** Homebrew's `maven` ran on its keg-only `openjdk`
  dependency, which was **26.0.2**. Nix `maven` bundles **Zulu 21.0.11**. So
  builds moved from JDK 26 to JDK 21.

  This is arguably a fix rather than a regression: `java` on `PATH` is
  `/usr/bin/java`, which resolves to a hand-installed **GraalVM 21.0.7** in
  `~/Library/Java`, so compile and runtime now agree on 21 where they used to
  disagree by five major versions. `JAVA_HOME` is unset, so nothing was pinning
  it either way.

  If a project needs a specific JDK, pin it explicitly rather than relying on
  whatever maven bundles:

  ```sh
  export JAVA_HOME=$(/usr/libexec/java_home)   # the GraalVM 21 above
  ```

  The GraalVM install is the last thing on this machine owned by neither Nix nor
  Homebrew. Declaring a JDK in `home.packages` and setting `JAVA_HOME` from it
  would close that gap, at the cost of no longer using GraalVM specifically.

  **Superseded by the Java section below.** `jenv` plus its export plugin now
  sets `JAVA_HOME`, so neither the manual `export` above nor maven's bundled
  Zulu decides the JDK any more.

- The `PATH` entry for IntelliJ's bundled maven
  (`/Applications/IntelliJ IDEA.app/Contents/plugins/maven/lib/maven3/bin`) does
  not exist on disk - recent IntelliJ moved it. The line in `~/.zshrc` is inert
  and can be deleted.
- `colima start` still finds its VM state in `~/.colima`.
- `gpg` still reads `~/.gnupg` and the agent can prompt. No `gpg-agent.conf`
  change is needed: nixpkgs builds gnupg on darwin with `pinentry-mac` in its
  own closure as the compiled-in default. `pinentry_mac` is also listed in
  `home.packages` so the binary is directly invocable.
- `ls`/`find` are the GNU versions, not the BSD ones macOS ships.
- `ollama list` still sees the models in `~/.ollama`.

## Switch 3 (done): `~/.zshrc` ported to Home Manager

Home Manager now owns `~/.zshrc`, `~/.zshenv` and `~/.zprofile`. oh-my-zsh comes
from nixpkgs rather than the `~/.oh-my-zsh` git clone, which is now unused and
can be deleted - its `custom/` directory held only the shipped `.zsh-template`
examples.

| Was | Now |
| --- | --- |
| `source $ZSH/oh-my-zsh.sh` | `programs.zsh.oh-my-zsh.enable`; `$ZSH` is set in the generated `.zshenv` |
| `plugins=(...)` | `oh-my-zsh.plugins`. `colorize` needs a highlighter, so `chroma` is in `home.packages`. |
| `eval "$(starship init zsh)"` | emitted automatically now that zsh is HM-managed |
| `export LANG`, `FZF_DEFAULT_COMMAND` | `programs.zsh.sessionVariables` -> generated `.zshenv` |
| `COMPLETION_WAITING_DOTS` | `localVariables` |
| `GPG_TTY=$(tty)`, ssh/EDITOR branch, `pyenv init` | `initContent` - all need per-shell evaluation |
| `export PATH="$HOME/.local/bin:$PATH"` | `home.sessionPath` |
| `~/.zshenv`: `. "$HOME/.cargo/env"` | `programs.zsh.envExtra` |
| `~/.zprofile`: `brew shellenv` | `programs.zsh.profileExtra` |
| IntelliJ maven `PATH` entry | **deleted** - recent IntelliJ moved it, the directory does not exist |

`/etc/zshrc` caps history at 2000 lines; `programs.zsh.history` raises it to
50000 with timestamps, dedup and sharing.

### The `~/.zshrc.local` hook

The last line of the generated `.zshrc` is:

```sh
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
```

It is emitted with `lib.mkAfter` (order 1500) deliberately. The HM zsh module
writes `shellAliases` at order 1100 and zsh-syntax-highlighting at 1200, so a
plain `initContent` string would land *before* them and the local file could not
actually override anything.

`~/.zshrc.local` is untracked and holds everything that must not enter a public
repo: the CMS `gateway_run` / `gateway_debug` / `cpyolo` aliases and
`source ~/.config/cms-secrets.env` (which exports `ANYTHINGLLM_API_KEY`,
`SONARQUBE_TOKEN`, `JIRA_CMS_TOKEN`). Recreate it by hand on a new machine.

### Testing a shell config before activating it

`ZDOTDIR` makes this cheap - point a throwaway login shell at the built
`home-manager-files` output and exercise it without touching the real dotfiles:

```sh
HMF=$(nix-store -qR <system-closure> | grep -m1 home-manager-files)
env -i HOME="$HOME" USER="$USER" TERM=xterm HISTFILE=/dev/null \
  ZDOTDIR="$HMF" /bin/zsh -l -i -c 'alias cc; command -v cargo; bindkey "^f"'
```

## Rust

`rustup` comes from nixpkgs, which ships the same 1.29.0 and the same 14 proxy
binaries the hand-installed one did. Only the proxies are declared - toolchains
stay mutable in `~/.rustup`, so `rust-toolchain.toml`, `rustup override` and
nightly all keep working. Declaring `rustc`/`cargo` from nixpkgs instead would
pin one compiler version and give that up.

The hand-installed rustup previously appended
`. "$HOME/.cargo/env"` to `~/.zshenv`, and that script **prepends**
`~/.cargo/bin`, putting it ahead of the Nix profile. That is how a
`cargo install`ed `tree-sitter` came to shadow the declared one. The line is
gone; `initContent` now does

```sh
path+=("$HOME/.cargo/bin")
```

which **appends**, so `cargo install`ed tools stay reachable but rank below
everything declared. Note `home.sessionPath` cannot be used for this - it
prepends.

Everything currently in `~/.cargo/bin` is a symlink to the old rustup proxy and
is now dead weight; the directory is only kept on `PATH` for future
`cargo install` output.

## Java (jenv, Corretto 21 and 25)

The EDI Gateway project is moving from Java 21 to Java 25 and needs both
installed at once, so `jenv` owns the `java`/`javac` shims and both JDKs are
declared casks. `.java-version` in a project directory then selects the JDK.

Corretto 21 is declared even though the machine already had a hand-installed
**GraalVM 21** in `~/Library/Java`. Comparing GraalVM 21 against Corretto 25
would cross a vendor boundary as well as a version boundary, which is the wrong
shape for a compatibility-regression comparison. GraalVM is registered with
`jenv` too and nothing was removed, so it is still selectable by name.

Like `~/.rustup` and `~/.pyenv`, the contents of `~/.jenv` stay mutable rather
than declared - `jenv add` records a JDK. README lists the commands.

### The export plugin is not optional here

nixpkgs wraps `mvn` as:

```sh
export JAVA_HOME=${JAVA_HOME-'/nix/store/...-zulu-ca-jdk-21.0.11'}
```

`${JAVA_HOME-default}` substitutes only when `JAVA_HOME` is **unset**, and it
was unset on this machine. jenv's shims cover `java` and `javac`, not Maven's
choice of JDK, so with shims alone `jenv global 25` would change `java -version`
while `mvn` silently kept compiling against Zulu 21.0.11 - the exact
compile/runtime split that the Switch 2 notes above flagged as already fixed.

`jenv enable-plugin export` makes jenv set `JAVA_HOME` per selected version,
which wins over the wrapper's default and puts `mvn` back under jenv's control.
Verify with `mvn -version`, not just `java -version`; only the former reads
`JAVA_HOME`.

## Still not reproducible

- **GraalVM 21** in `~/Library/Java`, which `/usr/bin/java` resolves to. No
  longer what builds run on - see the Java section above - but still owned by
  neither package manager.
- **`~/.config/cms-secrets.env`**, which must stay that way.

Mutable per-tool state that is deliberately not tracked: `~/.rustup`
toolchains, `~/.pyenv` interpreters, `~/.ollama` models, `~/.colima` VM state,
`~/.jenv` JDK registrations.
