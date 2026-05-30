ENV_FILE := .env

ifeq ($(wildcard $(ENV_FILE)),)
  ENV_FILE := .env.example
endif

.PHONY: generate bridge install-hooks install

generate:
	@set -a && . ./$(ENV_FILE) && set +a; \
	cd ios/ClaudeWatch && xcodegen generate

bridge:
	@set -a && . ./$(ENV_FILE) && set +a; \
	cd skill/bridge && npm install && node server.js

install-hooks:
	./skill/setup-hooks.sh

install: generate
	@set -a && . ./$(ENV_FILE) && set +a; \
	DERIVED="$$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name 'ClaudeWatch-*' -type d | head -1)/Build/Products"; \
	echo "📱 安装 iOS 伴侣 App..."; \
	xcrun devicectl device install app --device "$${IPHONE_ID}" "$$DERIVED/Debug-iphoneos/Agent Watch.app" 2>&1 | grep -E "installed|error"; \
	echo "⌚ 安装 Watch App..."; \
	xcrun devicectl device install app --device "$${WATCH_ID}" "$$DERIVED/Debug-watchos/Agent Watch.app" 2>&1 | grep -E "installed|error"; \
	echo "🚀 启动 Watch App..."; \
	xcrun devicectl device process launch --device "$${WATCH_ID}" $${BUNDLE_ID_PREFIX}.$${WATCH_BUNDLE_SUFFIX} 2>&1 | grep -E "Launched|error"; \
	echo "✅ 完成！"
