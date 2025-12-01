module.exports = function(api) {
  api.cache(true);
  return {
    presets: [
      'babel-preset-expo'
    ],
    plugins: [
      [
        'module-resolver',
        {
          alias: {
            '@': './src',
            '@screens': './src/screens',
            '@components': './src/components',
            '@services': './src/services',
            '@store': './src/store',
            '@utils': './src/utils',
            '@types': './src/types',
            '@config': './src/config',
            '@theme': './src/theme',
            '@contexts': './src/contexts',
            '@hooks': './src/hooks',
          },
        },
      ],
      'react-native-reanimated/plugin',
    ],
  };
};
