library pubviz.viz_root;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:collection/wrappers.dart';

import 'dependency.dart';
import 'viz_package.dart';

class VizRoot {
  final VizPackage root;
  final Map<String, VizPackage> packages;

  VizRoot._(this.root, Map<String, VizPackage> packages)
      : this.packages = new UnmodifiableMapView(packages);

  static Future<VizRoot> forDirectory(String path) async {
    var root = await VizPackage.forDirectory(path);
    var packages = await _getReferencedPackages(path);
    if (!packages.containsKey(root.name)) {
      // the current package likely has no lib dir
      var rootLibDirPath = p.join(path, 'lib');
      var rootLibDir = new Directory(rootLibDirPath);
      assert(!rootLibDir.existsSync());
      packages[root.name] = root;
    }
    assert(packages.containsKey(root.name));

    // want to make sure that the root note instance is the same
    // as the instance in the packages collection
    root = packages[root.name];

    return new VizRoot._(root, packages);
  }

  String toDot({bool escapeLabels: false}) {
    _update();

    var sink = new StringBuffer();
    sink.writeln('digraph G {');
    sink.writeln('  node [fontname=Helvetica];');
    sink.writeln('  edge [fontname=Helvetica, fontcolor=gray];');

    for (var pack in packages.values) {
      sink.writeln();

      pack.write(sink, root.name, escapeLabels: escapeLabels);
    }

    sink.writeln('}');

    return sink.toString();
  }

  void _update() {
    if (root.isPrimary == false) {
      root.isPrimary = true;

      assert(root.onlyDev);
      root.onlyDev = false;

      for (var primaryDep in root.dependencies) {
        var package = packages[primaryDep.name];

        assert(!package.isPrimary);
        package.isPrimary = true;

        if (!primaryDep.isDevDependency) {
          _updateDevOnly(primaryDep);
        }
      }
    }
  }

  void _updateDevOnly(Dependency dep) {
    var package = packages[dep.name];

    if (package.onlyDev) {
      package.onlyDev = false;

      for (var subDep
          in package.dependencies.where((d) => !d.isDevDependency)) {
        _updateDevOnly(subDep);
      }
    }
  }
}

Future<Map<String, String>> _getPackageMap(String path) async {
  var map = new Map<String, String>();

  var result = await Process.run('pub', ['list-package-dirs']);
  var json = JSON.decode(result.stdout as String);

  var packages = json['packages'] as Map;

  packages.forEach((k, v) {
    assert(p.basename(v) == 'lib');
    map[k] = p.dirname(v);
  });

  return map;
}

Future<Map<String, VizPackage>> _getReferencedPackages(String path) async {
  var packs = new Map<String, VizPackage>();

  var map = await _getPackageMap(path);

  for (var packageName in map.keys) {
    var subPath = map[packageName];
    var vp = await VizPackage.forDirectory(subPath);
    assert(vp.name == packageName);

    assert(!packs.containsKey(vp.name));
    assert(!packs.containsValue(vp));
    packs[vp.name] = vp;
  }
  return packs;
}