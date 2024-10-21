install_cairo_native_runtime() {
	git clone https://github.com/lambdaclass/cairo_native.git
	pushd ./cairo_native || exit 1
	cargo build -p cairo-native-runtime --release --all-features --quiet
	popd || exit 1

	cp ./cairo_native/target/release/libcairo_native_runtime.a $(pwd)/libcairo_native_runtime.a
	rm -rf ./cairo_native

	export CAIRO_NATIVE_RUNTIME_LIBRARY="$(pwd)/libcairo_native_runtime.a"

  echo "CAIRO_NATIVE_RUNTIME_LIBRARY=$CAIRO_NATIVE_RUNTIME_LIBRARY"

	[ -n "$GITHUB_ACTIONS" ] && echo "CAIRO_NATIVE_RUNTIME_LIBRARY=$CAIRO_NATIVE_RUNTIME_LIBRARY" >> $GITHUB_ENV
}

install_cairo_native_runtime