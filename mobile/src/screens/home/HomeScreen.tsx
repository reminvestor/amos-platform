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
import { Settings, Mails, Contact, Globe, PlayCircle, MailPlus, UserPlus, GlobeLock, CirclePlus, ChevronRight, Send, UserRoundPlus, Globe2, CalendarDays, AlertCircle, CircleOff, CheckCircle, Circle } from 'lucide-react-native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchCampaigns } from '@store/slices/campaignsSlice';
import { fetchContacts, fetchContactGroups } from '@store/slices/contactsSlice';
import { fetchTasksDueToday, fetchOverdueTasks } from '@store/slices/tasksSlice';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import * as landingPageService from '@services/landing-pages';

interface HomeScreenProps {
  navigation: any;
}

interface StatCard {
  title: string;
  value: string | number;
  Icon: React.ComponentType<any>;
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
  const { list: tasks, isLoading: tasksLoading } = useAppSelector(
    (state) => state.tasks
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
      await dispatch(fetchTasksDueToday());
      await dispatch(fetchOverdueTasks());
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
      Icon: Mails,
      color: colors.primary,
      onPress: () => navigation.navigate('Campaigns'),
    },
    {
      title: 'Total Contacts',
      value: contactPagination.total || 0,
      Icon: Contact,
      color: colors.success,
      onPress: () => navigation.navigate('Contacts'),
    },
    {
      title: 'Landing Pages',
      value: landingPages,
      Icon: Globe,
      color: colors.info,
      onPress: () => navigation.navigate('LandingPages'),
    },
    {
      title: 'Active Campaigns',
      value: campaigns.filter((c) => c.status === 'in_progress').length,
      Icon: PlayCircle,
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
      Icon: Send,
      time: '2 hours ago',
    },
    {
      id: '2',
      type: 'contact',
      title: 'Contacts Imported',
      description: '150 new contacts added',
      Icon: UserRoundPlus,
      time: '1 day ago',
    },
    {
      id: '3',
      type: 'landing',
      title: 'Landing Page Published',
      description: 'New landing page went live',
      Icon: Globe2,
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
            <Settings size={24} color={colors.primary} />
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
                    <stat.Icon size={24} color={stat.color} />
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
            <MailPlus size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Create Campaign</StyledText>
            <ChevronRight size={20} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.success }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate('Contacts')}
          >
            <UserPlus size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Add Contact</StyledText>
            <ChevronRight size={20} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.info }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate('LandingPages')}
          >
            <GlobeLock size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Create Landing Page</StyledText>
            <ChevronRight size={20} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.warning }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate('Tasks', { screen: 'TaskEdit', params: { mode: 'create' } })}
          >
            <CirclePlus size={20} color="#fff" />
            <StyledText style={styles.actionButtonText}>Create Task</StyledText>
            <ChevronRight size={20} color="#fff" />
          </TouchableOpacity>
        </View>

        {/* Task Widget */}
        <View style={styles.section}>
          <View style={styles.activityHeader}>
            <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Tasks</StyledText>
            <TouchableOpacity onPress={() => navigation.navigate('Tasks')}>
              <StyledText style={[styles.viewAll, { color: colors.primary }]}>View All</StyledText>
            </TouchableOpacity>
          </View>

          <View style={styles.taskWidgetContainer}>
            <TouchableOpacity
              style={[styles.taskWidgetCard, { backgroundColor: colors.primary, opacity: 0.1 }]}
              onPress={() => navigation.navigate('Tasks')}
              activeOpacity={0.7}
            >
              <View style={styles.taskWidgetContent}>
                <CalendarDays size={24} color={colors.primary} />
                <View style={{ marginLeft: 12, flex: 1 }}>
                  <StyledText style={[styles.taskWidgetValue, { color: colors.text }]}>
                    {tasks.filter((t) => t.status !== 'completed').length}
                  </StyledText>
                  <StyledText style={[styles.taskWidgetLabel, { color: colors.textSecondary }]}>
                    Due Today
                  </StyledText>
                </View>
              </View>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.taskWidgetCard, { backgroundColor: colors.error, opacity: 0.1 }]}
              onPress={() => navigation.navigate('Tasks', { screen: 'TaskList', params: { filter: 'overdue' } })}
              activeOpacity={0.7}
            >
              <View style={styles.taskWidgetContent}>
                <AlertCircle size={24} color={colors.error} />
                <View style={{ marginLeft: 12, flex: 1 }}>
                  <StyledText style={[styles.taskWidgetValue, { color: colors.text }]}>
                    {tasks.filter(
                      (t) =>
                        t.due_date &&
                        new Date(t.due_date) < new Date() &&
                        t.status !== 'completed'
                    ).length}
                  </StyledText>
                  <StyledText style={[styles.taskWidgetLabel, { color: colors.textSecondary }]}>
                    Overdue
                  </StyledText>
                </View>
              </View>
            </TouchableOpacity>
          </View>

          {tasks.length === 0 && (
            <View style={[styles.emptyState, { backgroundColor: colors.surface }]}>
              <CircleOff size={32} color={colors.textSecondary} />
              <StyledText style={[styles.emptyStateText, { color: colors.textSecondary }]}>
                No tasks yet. Create one to get started!
              </StyledText>
            </View>
          )}

          {tasks.length > 0 && (
            <View>
              {tasks.slice(0, 2).map((task, index) => (
                <TouchableOpacity
                  key={task.id}
                  onPress={() =>
                    navigation.navigate('Tasks', { screen: 'TaskDetail', params: { taskId: task.id } })
                  }
                  style={[
                    styles.taskItem,
                    {
                      borderBottomColor: colors.border,
                      borderBottomWidth: index < 1 ? 1 : 0,
                    },
                  ]}
                >
                  <View
                    style={[
                      styles.taskItemIcon,
                      {
                        backgroundColor:
                          task.status === 'completed'
                            ? `${colors.success}15`
                            : `${colors.warning}15`,
                      },
                    ]}
                  >
                    {task.status === 'completed' ? (
                      <CheckCircle size={16} color={colors.success} />
                    ) : (
                      <Circle size={16} color={colors.warning} />
                    )}
                  </View>

                  <View style={{ flex: 1 }}>
                    <StyledText
                      style={[
                        styles.taskItemTitle,
                        {
                          color: colors.text,
                          textDecorationLine:
                            task.status === 'completed' ? 'line-through' : 'none',
                        },
                      ]}
                      numberOfLines={1}
                    >
                      {task.title}
                    </StyledText>
                    <StyledText
                      style={[styles.taskItemDue, { color: colors.textSecondary }]}
                    >
                      {task.due_date
                        ? new Date(task.due_date).toLocaleDateString('en-US', {
                            month: 'short',
                            day: 'numeric',
                          })
                        : 'No due date'}
                    </StyledText>
                  </View>

                  <View
                    style={[
                      styles.taskPriorityBadge,
                      {
                        backgroundColor:
                          task.priority === 'high'
                            ? colors.error
                            : task.priority === 'medium'
                            ? colors.warning
                            : colors.success,
                      },
                    ]}
                  />
                </TouchableOpacity>
              ))}
            </View>
          )}
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
                <activity.Icon
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
  taskWidgetContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 16,
  },
  taskWidgetCard: {
    flex: 1,
    borderRadius: 10,
    padding: 12,
  },
  taskWidgetContent: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  taskWidgetValue: {
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 2,
  },
  taskWidgetLabel: {
    fontSize: 12,
  },
  emptyState: {
    borderRadius: 10,
    padding: 20,
    alignItems: 'center',
    marginBottom: 12,
  },
  emptyStateText: {
    fontSize: 14,
    marginTop: 8,
    textAlign: 'center',
  },
  taskItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
  },
  taskItemIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  taskItemTitle: {
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 2,
  },
  taskItemDue: {
    fontSize: 12,
  },
  taskPriorityBadge: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginLeft: 8,
  },
});
