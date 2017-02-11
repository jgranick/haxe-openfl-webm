mkdir ndll/Android 2> /dev/null
pushd project
haxelib run hxcpp Build.xml -Dandroid -v
haxelib run hxcpp Build.xml -Dandroid -DHXCPP_ARMV7 -v
popd