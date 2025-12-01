import React, { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { NavigationContainer, useNavigationState } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Building2, Bot, Settings2, Settings } from 'lucide-react-native';
import { SegmentedButtons } from 'react-native-paper';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import AppHeader from '@components/AppHeader';
import GlobalChatInput from '@components/GlobalChatInput';

// Auth Screens (will be created)
import LoginScreen from '@screens/auth/LoginScreen';
import ForgotPasswordScreen from '@screens/auth/ForgotPasswordScreen';
import MFAVerificationScreen from '@screens/auth/MFAVerificationScreen';

// Main Screens (will be created)
import ChatScreen from '@screens/chat/ChatScreen';
import CampaignListScreen from '@screens/campaigns/CampaignListScreen';
import CampaignDetailScreen from '@screens/campaigns/CampaignDetailScreen';
import ContactListScreen from '@screens/contacts/ContactListScreen';
import AddContactScreen from '@screens/contacts/AddContactScreen';
import LandingPageListScreen from '@screens/landing-pages/LandingPageListScreen';
import AgentListScreen from '@screens/agents/AgentListScreen';
import AgentDetailScreen from '@screens/agents/AgentDetailScreen';
import SettingsScreen from '@screens/settings/SettingsScreen';
import TermsScreen from '@screens/legal/TermsScreen';
import PrivacyPolicyScreen from '@screens/legal/PrivacyPolicyScreen';

const Stack = createNativeStackNavigator();
const Tab = createBottomTabNavigator();

/**
 * Auth Navigator - Shown to unauthenticated users
 */
export function AuthNavigator() {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen name="Login" component={LoginScreen} />
      <Stack.Screen name="MFAVerification" component={MFAVerificationScreen} />
      <Stack.Screen
        name="ForgotPassword"
        component={ForgotPasswordScreen}
        options={{
          contentStyle: { backgroundColor: colors.background },
        }}
      />
      <Stack.Screen
        name="Terms"
        component={TermsScreen}
        options={{
          headerShown: true,
          title: 'Terms of Service',
        }}
      />
      <Stack.Screen
        name="Privacy"
        component={PrivacyPolicyScreen}
        options={{
          headerShown: true,
          title: 'Privacy Policy',
        }}
      />
    </Stack.Navigator>
  );
}

/**
 * Entity Screen with Paper SegmentedButtons
 */
function EntityWithSegments() {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const [activeTab, setActiveTab] = useState('campaigns');

  const renderContent = () => {
    switch (activeTab) {
      case 'campaigns':
        return <CampaignListScreen />;
      case 'contacts':
        return <ContactListScreen />;
      case 'pages':
        return <LandingPageListScreen />;
      default:
        return <CampaignListScreen />;
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View style={[segmentStyles.container, { backgroundColor: colors.surface, borderBottomColor: colors.border }]}>
        <SegmentedButtons
          value={activeTab}
          onValueChange={setActiveTab}
          buttons={[
            { value: 'campaigns', label: 'Campaigns' },
            { value: 'contacts', label: 'Contacts' },
            { value: 'pages', label: 'Pages' },
          ]}
          style={segmentStyles.segmentedButtons}
        />
      </View>
      <View style={{ flex: 1 }}>
        {renderContent()}
      </View>
    </View>
  );
}

const segmentStyles = StyleSheet.create({
  container: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  segmentedButtons: {
    borderRadius: 4, // Reduced from 8 for more squared look
  },
});

/**
 * Entity Navigator Stack - Wraps segment tabs with stack for detail screens
 */
function EntityNavigator() {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        headerBackTitleVisible: false,
        headerStyle: { backgroundColor: colors.surface },
        headerTintColor: colors.text,
      }}
    >
      <Stack.Screen
        name="EntityMain"
        component={EntityWithSegments}
      />
      <Stack.Screen
        name="CampaignDetail"
        component={CampaignDetailScreen}
        options={{ headerShown: true, title: 'Campaign Details' }}
      />
      <Stack.Screen
        name="AddContact"
        component={AddContactScreen}
        options={{ headerShown: true, title: 'Add Contact' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Agent Navigator Stack
 */
function AgentNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="AgentList"
        component={AgentListScreen}
      />
      <Stack.Screen
        name="AgentDetail"
        component={AgentDetailScreen}
        options={{ headerShown: true, title: 'Agent Details' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Settings Navigator Stack
 */
function SettingsNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="SettingsMain"
        component={SettingsScreen}
      />
      <Stack.Screen
        name="Terms"
        component={TermsScreen}
        options={{ headerShown: true, title: 'Terms of Service' }}
      />
      <Stack.Screen
        name="Privacy"
        component={PrivacyPolicyScreen}
        options={{ headerShown: true, title: 'Privacy Policy' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Main Tab Navigator - 4 tabs: Entity, AMOS, Agents, Settings
 */
function MainTabs({ onTabChange }: { onTabChange?: (tabName: string) => void }) {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarIcon: ({ color, size }) => {
          switch (route.name) {
            case 'Entity':
              return <Building2 size={size} color={color} />;
            case 'AMOS':
              return <Bot size={size} color={color} />;
            case 'Agents':
              return <Settings2 size={size} color={color} />;
            case 'Settings':
              return <Settings size={size} color={color} />;
            default:
              return <Bot size={size} color={color} />;
          }
        },
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textTertiary,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
        },
        tabBarLabelStyle: {
          fontSize: 12,
        },
      })}
      screenListeners={{
        state: (e) => {
          const state = e.data.state;
          if (state && onTabChange) {
            const currentRoute = state.routes[state.index];
            onTabChange(currentRoute.name);
          }
        },
      }}
    >
      <Tab.Screen
        name="AMOS"
        component={ChatScreen}
        options={{ title: 'AMOS' }}
      />
      <Tab.Screen
        name="Entity"
        component={EntityNavigator}
        options={{ title: 'Business' }}
      />
      <Tab.Screen
        name="Agents"
        component={AgentNavigator}
        options={{ title: 'Agents' }}
      />
      <Tab.Screen
        name="Settings"
        component={SettingsNavigator}
        options={{ title: 'Settings' }}
      />
    </Tab.Navigator>
  );
}

/**
 * Wrapper that adds AppHeader to main tabs
 */
function MainWithHeader() {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const { user } = useAppSelector((state) => state.auth);
  const entityName = user?.entity_name || 'Business';
  const [currentTab, setCurrentTab] = useState('AMOS');

  // Hide global chat input on AMOS tab since it has its own chat interface
  const showGlobalInput = currentTab !== 'AMOS';

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader showNewChat={true} subtitle={entityName} />
      <MainTabs onTabChange={setCurrentTab} />
      <GlobalChatInput visible={showGlobalInput} />
    </View>
  );
}

/**
 * Root Navigator - Main app navigation
 */
export function RootNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
      }}
    >
      <Stack.Screen name="Main" component={MainWithHeader} />
    </Stack.Navigator>
  );
}

