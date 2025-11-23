import React, { useEffect, useState } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchCampaigns } from '@store/slices/campaignsSlice';
import { fetchContacts, fetchContactGroups } from '@store/slices/contactsSlice';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import * as landingPageService from '@services/landing-pages';

interface HomeScreenProps {
  navigation: any;
}

interface StatCard {
  title: string;
  value: string | number;
  icon: string;
  color: string;
  onPress?: () => void;
}

export default function HomeScreen({ navigation }: HomeScreenProps) {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();

  const { theme } = useAppSelector((state) => state.ui);
  const { user } = useAppSelector((state) => state.auth);
  const { list: campaigns, pagination: campaignPagination, isLoading: campaignsLoading } = useAppSelector(
    (state) => state.campaigns
  );
  const { list: contacts, pagination: contactPagination, isLoading: contactsLoading } = useAppSelector(
    (state) => state.contacts
  );

  const colors = getColors(theme);

  const [landingPages, setLandingPages] = useState(0);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isLoadingLandingPages, setIsLoadingLandingPages] = useState(false);

  useEffect(() => {
    loadAllData();
  }, []);

  const loadAllData = async () => {
    try {
      await dispatch(fetchCampaigns({ page: 1, perPage: 1 }));
      await dispatch(fetchContacts({ page: 1, perPage: 1 }));
      loadLandingPages();
    } catch (error) {
      console.log('Error loading data:', error);
    }
  };

  const loadLandingPages = async () => {
    try {
      setIsLoadingLandingPages(true);
      const response = await landingPageService.getLandingPages({ page: 1, perPage: 1 });
      setLandingPages(response.pagination.total);
    } catch (error) {
      console.log('Error loading landing pages:', error);
    } finally {
      setIsLoadingLandingPages(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadAllData();
    setIsRefreshing(false);
  };

  const stats: StatCard[] = [
    {
      title: 'Total Campaigns',
      value: campaignPagination.total || 0,
      icon: 'email-multiple',
      color: colors.primary,
      onPress: () => navigation.navigate('Campaigns'),
    },
    {
      title: 'Total Contacts',
      value: contactPagination.total || 0,
      icon: 'contacts',
      color: colors.success,
      onPress: () => navigation.navigate('Contacts'),
    },
    {
      title: 'Landing Pages',
      value: landingPages,
      icon: 'web',
      color: colors.info,
      onPress: () => navigation.navigate('LandingPages'),
    },
    {
      title: 'Active Campaigns',
      value: campaigns.filter((c) => c.status === 'in_progress').length,
      icon: 'play-circle',
      color: colors.warning,
      onPress: () => navigation.navigate('Campaigns'),
    },
  ];

  const recentActivity = [
    {
      id: '1',
      type: 'campaign',
      title: 'Campaign Created',
      description: 'New campaign started',
      icon: 'email-send',
      time: '2 hours ago',
    },
    {
      id: '2',
      type: 'contact',
      title: 'Contacts Imported',
      description: '150 new contacts added',
      icon: 'account-multiple-plus',
      time: '1 day ago',
    },
    {
      id: '3',
      type: 'landing',
      title: 'Landing Page Published',
      description: 'New landing page went live',
      icon: 'web-check',
      time: '3 days ago',
    },
  ];

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 16 }]}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
      >
        {/* Header */}
        <View style={styles.header}>
          <View>
            <StyledText style={[styles.greeting, { color: colors.text }]}>
              Welcome back,
            </StyledText>
            <StyledText style={[styles.username, { color: colors.text }]}>
              {user?.name || 'User'}
            </StyledText>
          </View>
          <TouchableOpacity
            style={[styles.notificationButton, { backgroundColor: colors.surface }]}
            onPress={() => navigation.navigate('Settings')}
          >
            <MaterialCommunityIcons name="cog" size={24} color={colors.primary} />
          </TouchableOpacity>
        </View>

        {/* Stats Grid */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Overview</StyledText>

          <View style={styles.statsGrid}>
            {stats.map((stat) => (
              <View key={stat.title} style={styles.statCard}>
                <TouchableOpacity
                  style={[
                    styles.statCardInner,
                    { backgroundColor: colors.surface, borderColor: colors.border },
                  ]}
                  onPress={stat.onPress}
                  activeOpacity={0.7}
                >
                  <View
                    style={[
                      styles.statIconContainer,
                      { backgroundColor: `${stat.color}15` },
                    ]}
                  >
                    <MaterialCommunityIcons
                      name={stat.icon}
                      size={24}
                      color={stat.color}
                    />
                  </View>
                  <StyledText style={[styles.statValue, { color: colors.text }]}>
                    {isLoadingLandingPages && stat.title === 'Landing Pages' ? (
                      <ActivityIndicator size="small" color={colors.primary} />
                    ) : (
                      stat.value
                    )}
                  </StyledText>
                  <StyledText style={[styles.statLabel, { color: colors.textSecondary }]}>
                    {stat.title}
                  </StyledText>
                </TouchableOpacity>
              </View>
            ))}
          </View>
        </View>

        {/* Quick Actions */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Quick Actions</StyledText>

          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.primary }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate('Campaigns')}
          >
            <MaterialCommunityIcons name="email-plus" size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Create Campaign</StyledText>
            <MaterialCommunityIcons name="chevron-right" size={20} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.success }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate('Contacts')}
          >
            <MaterialCommunityIcons name="account-plus" size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Add Contact</StyledText>
            <MaterialCommunityIcons name="chevron-right" size={20} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.info }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate('LandingPages')}
          >
            <MaterialCommunityIcons name="web-plus" size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Create Landing Page</StyledText>
            <MaterialCommunityIcons name="chevron-right" size={20} color="#fff" />
          </TouchableOpacity>
        </View>

        {/* Recent Activity */}
        <View style={styles.section}>
          <View style={styles.activityHeader}>
            <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Recent Activity</StyledText>
            <TouchableOpacity onPress={() => navigation.navigate('Chat')}>
              <StyledText style={[styles.viewAll, { color: colors.primary }]}>View All</StyledText>
            </TouchableOpacity>
          </View>

          {recentActivity.map((activity) => (
            <View
              key={activity.id}
              style={[styles.activityItem, { borderBottomColor: colors.border }]}
            >
              <View
                style={[
                  styles.activityIconContainer,
                  {
                    backgroundColor: activity.type === 'campaign'
                      ? colors.primaryLight
                      : activity.type === 'contact'
                      ? `${colors.success}15`
                      : `${colors.info}15`,
                  },
                ]}
              >
                <MaterialCommunityIcons
                  name={activity.icon}
                  size={20}
                  color={activity.type === 'campaign'
                    ? colors.primary
                    : activity.type === 'contact'
                    ? colors.success
                    : colors.info}
                />
              </View>

              <View style={styles.activityContent}>
                <StyledText style={[styles.activityTitle, { color: colors.text }]}>
                  {activity.title}
                </StyledText>
                <StyledText style={[styles.activityDescription, { color: colors.textSecondary }]}>
                  {activity.description}
                </StyledText>
              </View>

              <StyledText style={[styles.activityTime, { color: colors.textTertiary }]}>
                {activity.time}
              </StyledText>
            </View>
          ))}
        </View>

        <View style={{ height: insets.bottom + 32 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 32,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 32,
  },
  greeting: {
    fontSize: 14,
    fontWeight: '500',
  },
  username: {
    fontSize: 28,
    fontWeight: '700',
    marginTop: 4,
  },
  notificationButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
  },
  section: {
    marginBottom: 28,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 16,
  },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginHorizontal: -6,
  },
  statCard: {
    width: '50%',
    paddingHorizontal: 6,
    marginBottom: 12,
  },
  statCardInner: {
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    alignItems: 'center',
  },
  statIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  statValue: {
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 12,
    textAlign: 'center',
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderRadius: 10,
    marginBottom: 10,
  },
  actionButtonText: {
    flex: 1,
    marginLeft: 12,
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
  activityHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  viewAll: {
    fontSize: 14,
    fontWeight: '500',
  },
  activityItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  activityIconContainer: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  activityContent: {
    flex: 1,
  },
  activityTitle: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 2,
  },
  activityDescription: {
    fontSize: 12,
  },
  activityTime: {
    fontSize: 12,
    marginLeft: 8,
  },
});
