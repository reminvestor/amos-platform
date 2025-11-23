import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { MaterialCommunityIcons } from '@expo/vector-icons';

// Auth Screens (will be created)
import LoginScreen from '@screens/auth/LoginScreen';
import ForgotPasswordScreen from '@screens/auth/ForgotPasswordScreen';

// Main Screens (will be created)
import ChatScreen from '@screens/chat/ChatScreen';
import CampaignListScreen from '@screens/campaigns/CampaignListScreen';
import CampaignDetailScreen from '@screens/campaigns/CampaignDetailScreen';
import ContactListScreen from '@screens/contacts/ContactListScreen';
import LandingPageListScreen from '@screens/landing-pages/LandingPageListScreen';
import TaskListScreen from '@screens/tasks/TaskListScreen';
import TaskDetailScreen from '@screens/tasks/TaskDetailScreen';
import TaskEditScreen from '@screens/tasks/TaskEditScreen';
import AgentListScreen from '@screens/agents/AgentListScreen';
import AgentDetailScreen from '@screens/agents/AgentDetailScreen';
import SettingsScreen from '@screens/settings/SettingsScreen';

const Stack = createNativeStackNavigator();
const Tab = createBottomTabNavigator();

/**
 * Auth Navigator - Shown to unauthenticated users
 */
export function AuthNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        cardStyle: { backgroundColor: 'white' },
      }}
    >
      <Stack.Screen name="Login" component={LoginScreen} />
      <Stack.Screen
        name="ForgotPassword"
        component={ForgotPasswordScreen}
        options={{
          cardStyle: { backgroundColor: 'white' },
        }}
      />
    </Stack.Navigator>
  );
}

/**
 * Chat Navigator Stack
 */
function ChatNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="ChatMain"
        component={ChatScreen}
        options={{ title: 'Amos AI' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Campaign Navigator Stack
 */
function CampaignNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="CampaignList"
        component={CampaignListScreen}
        options={{ title: 'Campaigns' }}
      />
      <Stack.Screen
        name="CampaignDetail"
        component={CampaignDetailScreen}
        options={{ title: 'Campaign Details' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Contact Navigator Stack
 */
function ContactNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="ContactList"
        component={ContactListScreen}
        options={{ title: 'Contacts' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Landing Page Navigator Stack
 */
function LandingPageNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="LandingPageList"
        component={LandingPageListScreen}
        options={{ title: 'Landing Pages' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Task Navigator Stack
 */
function TaskNavigator() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="TaskList"
        component={TaskListScreen}
        options={{ title: 'Tasks' }}
      />
      <Stack.Screen
        name="TaskDetail"
        component={TaskDetailScreen}
        options={{ title: 'Task Details' }}
      />
      <Stack.Screen
        name="TaskEdit"
        component={TaskEditScreen}
        options={{ title: 'Edit Task' }}
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
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="AgentList"
        component={AgentListScreen}
        options={{ title: 'Agents' }}
      />
      <Stack.Screen
        name="AgentDetail"
        component={AgentDetailScreen}
        options={{ title: 'Agent Details' }}
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
        headerShown: true,
        headerBackTitleVisible: false,
      }}
    >
      <Stack.Screen
        name="SettingsMain"
        component={SettingsScreen}
        options={{ title: 'Settings' }}
      />
    </Stack.Navigator>
  );
}

/**
 * Root Navigator - Main app navigation
 */
export function RootNavigator() {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarIcon: ({ color, size }) => {
          let iconName = 'help';

          switch (route.name) {
            case 'Chat':
              iconName = 'chat';
              break;
            case 'Campaigns':
              iconName = 'email';
              break;
            case 'Contacts':
              iconName = 'account-multiple';
              break;
            case 'LandingPages':
              iconName = 'file-document';
              break;
            case 'Tasks':
              iconName = 'checkbox-marked-circle-outline';
              break;
            case 'Agents':
              iconName = 'robot';
              break;
            case 'Settings':
              iconName = 'cog';
              break;
          }

          return (
            <MaterialCommunityIcons name={iconName as any} size={size} color={color} />
          );
        },
        tabBarActiveTintColor: '#4A90E2',
        tabBarInactiveTintColor: '#999',
        tabBarLabelStyle: {
          fontSize: 12,
        },
      })}
    >
      <Tab.Screen
        name="Chat"
        component={ChatNavigator}
        options={{ title: 'Chat' }}
      />
      <Tab.Screen
        name="Campaigns"
        component={CampaignNavigator}
        options={{ title: 'Campaigns' }}
      />
      <Tab.Screen
        name="Contacts"
        component={ContactNavigator}
        options={{ title: 'Contacts' }}
      />
      <Tab.Screen
        name="LandingPages"
        component={LandingPageNavigator}
        options={{ title: 'Pages' }}
      />
      <Tab.Screen
        name="Tasks"
        component={TaskNavigator}
        options={{ title: 'Tasks' }}
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
