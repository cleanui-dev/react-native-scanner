/** @type {import('jest').Config} */
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.tsx'],
  // Resolve the library to its source (it is mocked in jest.setup.tsx, but
  // this keeps resolution working even when ../lib hasn't been built)
  moduleNameMapper: {
    '^@cleanuidev/react-native-scanner$': '<rootDir>/../src/index.tsx',
  },
  testPathIgnorePatterns: ['/node_modules/', '/android/', '/ios/'],
};
