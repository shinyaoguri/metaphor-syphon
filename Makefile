.PHONY: all setup submodules syphon clean-syphon build test ci-check verify check-registration check-pin clean

all: setup build

# 初回セットアップ: submodule + Syphon.xcframework のローカルビルド（Xcode.app が必要）。
# Frameworks/ は gitignore 済み。あれば Package.swift がそちらを優先し、無ければ Release asset を取る。
setup: submodules syphon

submodules:
	@echo "Updating submodules..."
	git submodule update --init --recursive

# Frameworks/ の有無で Package.swift の評価結果（binaryTarget が path か url か）が変わるが、
# SwiftPM は manifest の評価結果を内容ハッシュで共有キャッシュ（~/Library/Caches/org.swift.swiftpm）
# に持ち、ファイルの出現・消失では無効化しない（実測: 焼いた後も url 側のまま resolve される）。
# 焼く・消すの後は purge-cache で再評価させる。
syphon:
	@echo "Building Syphon.xcframework..."
	./scripts/build-syphon.sh
	swift package purge-cache

# ローカルビルドを退避して Release asset 側（consumer と同じ経路）で確かめたいとき
clean-syphon:
	rm -rf Frameworks .build/syphon
	swift package purge-cache

build:
	swift build

test:
	swift test

# CI の build-and-test と同条件（-Xswiftc -warnings-as-errors）。push 前に通す。
ci-check:
	swift build -Xswiftc -warnings-as-errors
	swift test -Xswiftc -warnings-as-errors

# workflow / シェルスクリプトの静的検査 + Python テスト（CI の validate）
verify:
	./scripts/verify.sh

# 別パッケージからの自動登録を debug / release で実行確認（CI の registration-matrix）
check-registration:
	./scripts/check-registration.sh

# Package.swift の binaryTarget pin が実在する asset と一致するか
check-pin:
	./scripts/check-syphon-pin.sh

clean:
	rm -rf .build
