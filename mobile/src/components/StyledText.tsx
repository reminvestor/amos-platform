import React from 'react';
import { Text, TextProps, StyleSheet } from 'react-native';

interface StyledTextProps extends TextProps {
  style?: any;
}

export const StyledText: React.FC<StyledTextProps> = ({ style, ...props }) => {
  return <Text {...props} style={[styles.default, style]} />;
};

const styles = StyleSheet.create({
  default: {
    fontFamily: 'System',
  },
});
