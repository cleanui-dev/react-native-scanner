const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const root = path.resolve(__dirname, '..');
const pkg = require('../package.json');

const escape = (s) => s.replace(/[|\\{}()[\]^$+*?.]/g, '\\$&');

const config = getDefaultConfig(__dirname);

// Watch the library source so edits in ../src hot reload
config.watchFolders = [root];

// Only resolve dependencies from this app, never the repo root's node_modules
// (the root has its own react-native version for development)
config.resolver.nodeModulesPaths = [path.resolve(__dirname, 'node_modules')];
config.resolver.disableHierarchicalLookup = true;
config.resolver.blockList = [
  new RegExp(`^${escape(path.join(root, 'node_modules'))}\\/.*$`),
  new RegExp(`^${escape(path.join(root, 'example'))}\\/.*$`),
  new RegExp(`^${escape(path.join(root, 'lib'))}\\/.*$`),
];

// Point the library at its TypeScript source instead of the built lib/
const libraryEntry = path.join(root, 'src', 'index.tsx');
const defaultResolveRequest = config.resolver.resolveRequest;
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName === pkg.name) {
    return { type: 'sourceFile', filePath: libraryEntry };
  }
  return (defaultResolveRequest ?? context.resolveRequest)(
    context,
    moduleName,
    platform
  );
};

module.exports = config;
