# Examples/Makefile — runnable demo helpers.
#
# `client-server-tcp-demo` exercises the headless `ClientServerTCPDemo` over a REAL TCP transport,
# across an OS boundary: a server on one OS and a client on the other, in BOTH directions.
#   • macOS side  — the native binary built into the nested package's `.build/`.
#   • Linux side  — the same sources built into the nested package's `.build-linux/` and run inside
#                   a `swift` Docker container (using whatever Docker runtime engine is active).
#
# The server binds `0.0.0.0`, so:
#   • Linux server: published with `-p $(PORT):$(PORT)` ⇒ the macOS host dials `127.0.0.1:$(PORT)`.
#   • macOS server: the Linux container dials it back via `host.docker.internal:$(PORT)`.
#
# Usage:
#   make build-all                                      # build every nested Swift package
#   make BUILD_CONFIGURATION=release build-all          # release build for every package
#   make -C Examples client-server-tcp-demo                 # both directions (default)
#   make -C Examples client-server-tcp-demo-linux-server    # Docker-Linux server + macOS client
#   make -C Examples client-server-tcp-demo-mac-server      # macOS server + Docker-Linux client
#   make -C Examples client-server-tcp-demo-mac             # both ends on macOS (no Docker)
#   make -C Examples PORT=9100 client-server-tcp-demo       # override the port

# /dev/tcp readiness probe below needs bash (not POSIX sh).
SHELL := /bin/bash

PORT        ?= 9099
SWIFT_IMAGE ?= swift:6.3
DEMO        := ClientServerTCPDemo
CLIENT_SERVER_PACKAGE_DIR := ClientServer
PEER_TO_PEER_PACKAGE_DIR  := PeerToPeer
PACKAGE_DIRS := DemoSupport DemoTransport $(CLIENT_SERVER_PACKAGE_DIR) $(PEER_TO_PEER_PACKAGE_DIR)
BUILD_CONFIGURATION ?= debug

# The nested demo packages reference the parent library by `path: "../.."`, so the whole repo root
# must be mounted into the container (not just `Examples/`).
REPO_ROOT := $(realpath $(CURDIR)/..)
REPO_NAME := $(notdir $(REPO_ROOT))
WORKDIR   := /work/$(REPO_NAME)

MAC_BIN   := $(CLIENT_SERVER_PACKAGE_DIR)/.build/debug/$(DEMO)
LINUX_BIN := $(WORKDIR)/Examples/$(CLIENT_SERVER_PACKAGE_DIR)/.build-linux/debug/$(DEMO)

# Run a swift container with the repo root mounted and cwd at the nested package.
DOCKER_RUN_CLIENT_SERVER = docker run --rm -v "$(REPO_ROOT):$(WORKDIR)" -w "$(WORKDIR)/Examples/$(CLIENT_SERVER_PACKAGE_DIR)" "$(SWIFT_IMAGE)"
DOCKER_RUN_PEER_TO_PEER = docker run --rm -v "$(REPO_ROOT):$(WORKDIR)" -w "$(WORKDIR)/Examples/$(PEER_TO_PEER_PACKAGE_DIR)" "$(SWIFT_IMAGE)"

# Block until the macOS host can TCP-connect to 127.0.0.1:$(PORT) (works for both a host-native server
# and a container server published with `-p`). Single line so it composes inside a one-shell recipe.
WAIT_PORT = echo "  ⏳ waiting for server on :$(PORT) …"; for i in $$(seq 1 150); do ( exec 3<>/dev/tcp/127.0.0.1/$(PORT) ) >/dev/null 2>&1 && { exec 3>&-; break; }; sleep 0.2; done

# Block until 127.0.0.1:$(PORT) is FREE (no listener). Needed before starting a host-native server right
# after a published container server is torn down — Docker releases the forwarded port slightly after
# `docker stop` returns, and `SO_REUSEADDR` does not bypass an *actively-listening* socket.
WAIT_FREE = echo "  ⏳ waiting for :$(PORT) to be free …"; for i in $$(seq 1 150); do ( exec 3<>/dev/tcp/127.0.0.1/$(PORT) ) >/dev/null 2>&1 && { exec 3>&-; sleep 0.2; } || break; done

.PHONY: build-all
build-all:
	@case "$(BUILD_CONFIGURATION)" in debug|release) ;; *) echo "✗ BUILD_CONFIGURATION must be debug or release."; exit 1;; esac
	@echo "▶︎ building all Swift packages ($(BUILD_CONFIGURATION))"
	@set -e; \
	for package_dir in $(PACKAGE_DIRS); do \
		echo "  ⚙︎ building $$package_dir …"; \
		swift build --package-path "$$package_dir" -c "$(BUILD_CONFIGURATION)"; \
	done
	@echo "✅ build-all OK"

.PHONY: client-server-tcp-demo
client-server-tcp-demo: client-server-tcp-demo-linux-server client-server-tcp-demo-mac-server
	@echo "✅ cross-OS TCP demo OK — macOS ⇄ Docker Linux (both directions)"

# Docker-Linux server + macOS client.
.PHONY: client-server-tcp-demo-linux-server
client-server-tcp-demo-linux-server: _check-docker _build-mac _build-linux
	@echo "▶︎ Docker-Linux server  +  macOS client            (port $(PORT))"
	@cid=$$(docker run -d --rm -p $(PORT):$(PORT) -v "$(REPO_ROOT):$(WORKDIR)" -w "$(WORKDIR)/Examples/$(CLIENT_SERVER_PACKAGE_DIR)" "$(SWIFT_IMAGE)" "$(LINUX_BIN)" server $(PORT)) || exit 1; \
	trap 'docker stop $$cid >/dev/null 2>&1 || true' EXIT; \
	$(WAIT_PORT); \
	"$(MAC_BIN)" client-auto 127.0.0.1 $(PORT)

# macOS server + Docker-Linux client.
.PHONY: client-server-tcp-demo-mac-server
client-server-tcp-demo-mac-server: _check-docker _build-mac _build-linux
	@echo "▶︎ macOS server  +  Docker-Linux client            (port $(PORT))"
	@$(WAIT_FREE); \
	"$(MAC_BIN)" server $(PORT) & spid=$$!; \
	trap 'kill $$spid >/dev/null 2>&1 || true' EXIT; \
	$(WAIT_PORT); \
	$(DOCKER_RUN_CLIENT_SERVER) "$(LINUX_BIN)" client-auto host.docker.internal $(PORT)

# Both ends on macOS — handy sanity check that needs no Docker.
.PHONY: client-server-tcp-demo-mac
client-server-tcp-demo-mac: _build-mac
	@echo "▶︎ macOS server  +  macOS client                   (port $(PORT))"
	@$(WAIT_FREE); \
	"$(MAC_BIN)" server $(PORT) & spid=$$!; \
	trap 'kill $$spid >/dev/null 2>&1 || true' EXIT; \
	$(WAIT_PORT); \
	"$(MAC_BIN)" client-auto 127.0.0.1 $(PORT)

.PHONY: _build-mac
_build-mac:
	@echo "  ⚙︎ building $(DEMO) for macOS ($(CLIENT_SERVER_PACKAGE_DIR)/.build/) …"
	@swift build --package-path "$(CLIENT_SERVER_PACKAGE_DIR)" --product "$(DEMO)"

.PHONY: _build-linux
_build-linux:
	@echo "  ⚙︎ building $(DEMO) for Linux ($(SWIFT_IMAGE) → .build-linux/) …"
	@$(DOCKER_RUN_CLIENT_SERVER) swift build --product "$(DEMO)" --scratch-path .build-linux

.PHONY: _check-docker
_check-docker:
	@docker info >/dev/null 2>&1 || { echo "✗ Docker engine not reachable — start the Docker runtime and retry."; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Peer-to-peer TCP demo — a real chat MESH across an OS boundary.
#
# Unlike client-server (one authoritative node), every peer owns its own
# `DistributedActomaton` and fans each post out to the others as a `.deliver`
# reverse letter. Two peers (`alice` on macOS, `bob` in a Docker-Linux
# container) each run `peer-auto`: both post a greeting, then each asserts it
# *received* the other's — so the mesh is verified in BOTH directions at once.
#
# `alice` < `bob`, so by the dial-ordering rule alice dials bob (the container's
# published port); bob only listens and waits for alice's inbound link. The
# `peer-auto` exit code is the assertion — the recipe requires BOTH to be 0.
#
# Usage:
#   make -C Examples peer-to-peer-tcp-demo            # macOS alice ⇄ Docker-Linux bob
#   make -C Examples peer-to-peer-tcp-demo-mac        # both peers on macOS (no Docker)
#   make -C Examples PORT_A=9090 PORT_B=9091 peer-to-peer-tcp-demo   # override ports
# ─────────────────────────────────────────────────────────────────────────────

PEER_DEMO      := PeerToPeerTCPDemo
PEER_BIN       := $(PEER_TO_PEER_PACKAGE_DIR)/.build/debug/$(PEER_DEMO)
LINUX_PEER_BIN := $(WORKDIR)/Examples/$(PEER_TO_PEER_PACKAGE_DIR)/.build-linux/debug/$(PEER_DEMO)
PORT_A         ?= 9098
PORT_B         ?= 9099

# Port-specific readiness probes for bob's listener on $(PORT_B) (the dialed-into side).
WAIT_PEER = echo "  ⏳ waiting for bob on :$(PORT_B) …"; for i in $$(seq 1 150); do ( exec 3<>/dev/tcp/127.0.0.1/$(PORT_B) ) >/dev/null 2>&1 && { exec 3>&-; break; }; sleep 0.2; done
FREE_PEER = echo "  ⏳ waiting for :$(PORT_B) to be free …"; for i in $$(seq 1 150); do ( exec 3<>/dev/tcp/127.0.0.1/$(PORT_B) ) >/dev/null 2>&1 && { exec 3>&-; sleep 0.2; } || break; done

# macOS alice + Docker-Linux bob — the headline cross-OS mesh round-trip.
.PHONY: peer-to-peer-tcp-demo
peer-to-peer-tcp-demo: _check-docker _build-peer-mac _build-peer-linux
	@echo "▶︎ cross-OS peer mesh: macOS alice  ⇄  Docker-Linux bob   (ports $(PORT_A)/$(PORT_B))"
	@$(FREE_PEER); \
	docker run --rm -p $(PORT_B):$(PORT_B) -v "$(REPO_ROOT):$(WORKDIR)" -w "$(WORKDIR)/Examples/$(PEER_TO_PEER_PACKAGE_DIR)" "$(SWIFT_IMAGE)" \
	    "$(LINUX_PEER_BIN)" peer-auto bob $(PORT_B) alice@host.docker.internal:$(PORT_A) & bpid=$$!; \
	trap 'kill $$bpid >/dev/null 2>&1 || true' EXIT; \
	$(WAIT_PEER); \
	"$(PEER_BIN)" peer-auto alice $(PORT_A) bob@127.0.0.1:$(PORT_B); astat=$$?; \
	wait $$bpid; bstat=$$?; \
	test $$astat -eq 0 -a $$bstat -eq 0
	@echo "✅ cross-OS peer-to-peer TCP demo OK — macOS ⇄ Docker Linux (both directions)"

# Both peers on macOS — handy sanity check that needs no Docker.
.PHONY: peer-to-peer-tcp-demo-mac
peer-to-peer-tcp-demo-mac: _build-peer-mac
	@echo "▶︎ macOS peer mesh: alice  ⇄  bob                         (ports $(PORT_A)/$(PORT_B))"
	@$(FREE_PEER); \
	"$(PEER_BIN)" peer-auto bob $(PORT_B) alice@127.0.0.1:$(PORT_A) & bpid=$$!; \
	trap 'kill $$bpid >/dev/null 2>&1 || true' EXIT; \
	$(WAIT_PEER); \
	"$(PEER_BIN)" peer-auto alice $(PORT_A) bob@127.0.0.1:$(PORT_B); astat=$$?; \
	wait $$bpid; bstat=$$?; \
	test $$astat -eq 0 -a $$bstat -eq 0
	@echo "✅ peer-to-peer TCP mesh OK — alice ⇄ bob (both directions)"

# Interactive chat — the headless analogue of `peer-to-peer-bonjour-demo`.
#
# `PeerToPeerTCPDemo` reads stdin, so (unlike the Bonjour GUI windows) several peers can't share one
# terminal's input. Instead this opens ONE macOS Terminal window per peer — each independently
# typeable — wiring them into a single mesh (`$(CHAT_BASE) + i` is peer i's port, 127.0.0.1). Type in
# any window and the message fans out to the others. Press Ctrl-C HERE to quit every peer at once (it
# waits on the peer processes and `pkill`s them on exit), or just `quit`/close each window.
#
# Usage:
#   make -C Examples peer-to-peer-tcp-demo-chat                          # 3 peers (alice bob carol)
#   make -C Examples PEERS="alice bob" peer-to-peer-tcp-demo-chat        # 2 peers
#   make -C Examples PEERS="a b c d" CHAT_BASE=9200 peer-to-peer-tcp-demo-chat
PEER_CHAT_NAMES ?= $(if $(filter command line,$(origin PEERS)),$(PEERS),alice bob carol)
CHAT_BASE ?= 9101

.PHONY: peer-to-peer-tcp-demo-chat
peer-to-peer-tcp-demo-chat: _build-peer-mac
	@command -v osascript >/dev/null 2>&1 || { echo "✗ osascript (macOS) required for the multi-window chat demo."; exit 1; }
	@bin="$(CURDIR)/$(PEER_BIN)"; names=($(PEER_CHAT_NAMES)); n=$${#names[@]}; \
	for i in $$(seq 0 $$((n - 1))); do \
		me=$${names[$$i]}; myport=$$(( $(CHAT_BASE) + i )); roster=""; \
		for j in $$(seq 0 $$((n - 1))); do \
			[ $$j -eq $$i ] && continue; \
			roster="$$roster $${names[$$j]}@127.0.0.1:$$(( $(CHAT_BASE) + j ))"; \
		done; \
		osascript -e "tell application \"Terminal\" to do script \"cd '$(CURDIR)'; '$$bin' peer $$me $$myport$$roster\"" >/dev/null; \
	done; \
	echo "▶︎ opened $$n Terminal windows [$(PEER_CHAT_NAMES)] — type in any window to chat across the mesh"; \
	echo "  press Ctrl-C HERE to quit all peers (or 'quit'/close each window)"; \
	trap 'pkill -f "$$bin" >/dev/null 2>&1 || true' INT TERM EXIT; \
	sleep 2; \
	while pgrep -f "$$bin" >/dev/null 2>&1; do sleep 1; done

.PHONY: _build-peer-mac
_build-peer-mac:
	@echo "  ⚙︎ building $(PEER_DEMO) for macOS ($(PEER_TO_PEER_PACKAGE_DIR)/.build/) …"
	@swift build --package-path "$(PEER_TO_PEER_PACKAGE_DIR)" --product "$(PEER_DEMO)"

.PHONY: _build-peer-linux
_build-peer-linux:
	@echo "  ⚙︎ building $(PEER_DEMO) for Linux ($(SWIFT_IMAGE) → .build-linux/) …"
	@$(DOCKER_RUN_PEER_TO_PEER) swift build --product "$(PEER_DEMO)" --scratch-path .build-linux

# ─────────────────────────────────────────────────────────────────────────────
# Bonjour GUI demo — one server + N clients as separate processes on ONE Mac.
#
# Each launch is one node; they discover each other over Bonjour on the local
# link (loopback included), so no second machine is needed to exercise the real
# `Network.framework` transport. The server broadcasts each `ServerSnapshot` to
# every subscribed client, so multiple clients all track the same counter live.
# All are SwiftUI windows; the `DemoAppDelegate` foregrounds each bundle-less
# binary and quits it when its window closes. Press Ctrl-C here to quit all.
#
# Usage:
#   make -C Examples client-server-bonjour-demo                       # server + 2 clients (Phone Tablet)
#   make -C Examples CLIENTS="Phone Tablet Laptop" client-server-bonjour-demo  # 3 clients
#   make -C Examples CLIENTS=Phone client-server-bonjour-demo         # just 1 client
# ─────────────────────────────────────────────────────────────────────────────

CLIENTS      ?= Phone Tablet
BONJOUR_DEMO := ClientServerBonjourDemo
BONJOUR_BIN  := $(CLIENT_SERVER_PACKAGE_DIR)/.build/debug/$(BONJOUR_DEMO)

.PHONY: client-server-bonjour-demo
client-server-bonjour-demo:
	@echo "  ⚙︎ building $(BONJOUR_DEMO) …"
	@swift build --package-path "$(CLIENT_SERVER_PACKAGE_DIR)" --product "$(BONJOUR_DEMO)"
	@echo "▶︎ Bonjour server + clients [$(CLIENTS)] (1 Mac, separate processes) — press Ctrl-C to quit all"
	@pids=""; \
	"$(BONJOUR_BIN)" server & pids="$$pids $$!"; \
	sleep 1; \
	for name in $(CLIENTS); do \
		"$(BONJOUR_BIN)" client $$name & pids="$$pids $$!"; \
	done; \
	trap 'kill $$pids >/dev/null 2>&1 || true' EXIT INT TERM; \
	wait

# ─────────────────────────────────────────────────────────────────────────────
# Bonjour GUI demo — N peers (chat mesh) as separate processes on ONE Mac.
#
# Each launch is one peer; they discover each other over Bonjour on the local
# link (loopback included) and wire the mesh reactively, so no second machine is
# needed. A message posted in one window echoes locally, then each *other* peer
# is resolved as a remote proxy and pushed a `.deliver` reverse letter. All are
# SwiftUI windows; press Ctrl-C here to quit all.
#
# Usage:
#   make -C Examples peer-to-peer-bonjour-demo                     # 2 peers (Alice Bob)
#   make -C Examples PEERS="Alice Bob Carol" peer-to-peer-bonjour-demo  # 3 peers
# ─────────────────────────────────────────────────────────────────────────────

BONJOUR_PEERS ?= $(if $(filter command line,$(origin PEERS)),$(PEERS),Alice Bob)
P2P_DEMO := PeerToPeerBonjourDemo
P2P_BIN  := $(PEER_TO_PEER_PACKAGE_DIR)/.build/debug/$(P2P_DEMO)

.PHONY: peer-to-peer-bonjour-demo
peer-to-peer-bonjour-demo:
	@echo "  ⚙︎ building $(P2P_DEMO) …"
	@swift build --package-path "$(PEER_TO_PEER_PACKAGE_DIR)" --product "$(P2P_DEMO)"
	@echo "▶︎ Bonjour peers [$(BONJOUR_PEERS)] (1 Mac, separate processes) — press Ctrl-C to quit all"
	@pids=""; \
	for name in $(BONJOUR_PEERS); do \
		"$(P2P_BIN)" $$name & pids="$$pids $$!"; \
	done; \
	trap 'kill $$pids >/dev/null 2>&1 || true' EXIT INT TERM; \
	wait
