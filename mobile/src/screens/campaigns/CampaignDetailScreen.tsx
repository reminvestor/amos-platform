import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function CampaignDetailScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.text}>Campaign Detail Screen</Text>
      <Text style={styles.subtitle}>Coming soon...</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#fff' },
  text: { fontSize: 18, fontWeight: 'bold', color: '#333' },
  subtitle: { fontSize: 14, color: '#666', marginTop: 8 },
});
