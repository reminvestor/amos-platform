import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Send, MailOpen, MousePointerClick, AlertCircle } from 'lucide-react-native';
import { LineChart, BarChart, PieChart } from 'react-native-chart-kit';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { formatPercentage, formatCurrency } from '@utils/formatters';

interface AnalyticsDashboardScreenProps {
  navigation: any;
  route: any;
}

interface AnalyticsData {
  period: 'week' | 'month' | 'year';
  campaignMetrics: {
    sent: number;
    opened: number;
    clicked: number;
    unsubscribed: number;
    bounced: number;
  };
  dailyMetrics: Array<{
    date: string;
    sends: number;
    opens: number;
    clicks: number;
  }>;
  topCampaigns: Array<{
    name: string;
    openRate: number;
    clickRate: number;
  }>;
  deviceMetrics: Record<string, number>;
}

export default function AnalyticsDashboardScreen({
  navigation,
  route,
}: AnalyticsDashboardScreenProps) {
  const insets = useSafeAreaInsets();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [period, setPeriod] = useState<'week' | 'month' | 'year'>('week');
  const [isLoading, setIsLoading] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [analyticsData, setAnalyticsData] = useState<AnalyticsData | null>(null);

  useEffect(() => {
    loadAnalytics();
  }, [period]);

  const loadAnalytics = async () => {
    setIsLoading(true);
    try {
      // Mock data for demonstration
      const mockData: AnalyticsData = {
        period,
        campaignMetrics: {
          sent: 15420,
          opened: 4285,
          clicked: 856,
          unsubscribed: 23,
          bounced: 142,
        },
        dailyMetrics: [
          { date: 'Mon', sends: 2500, opens: 650, clicks: 130 },
          { date: 'Tue', sends: 2200, opens: 580, clicks: 116 },
          { date: 'Wed', sends: 2800, opens: 750, clicks: 150 },
          { date: 'Thu', sends: 3100, opens: 820, clicks: 164 },
          { date: 'Fri', sends: 2700, opens: 730, clicks: 146 },
          { date: 'Sat', sends: 1100, opens: 280, clicks: 56 },
          { date: 'Sun', sends: 900, opens: 195, clicks: 39 },
        ],
        topCampaigns: [
          { name: 'Spring Sale', openRate: 0.35, clickRate: 0.08 },
          { name: 'Welcome Series', openRate: 0.42, clickRate: 0.12 },
          { name: 'New Product', openRate: 0.28, clickRate: 0.06 },
        ],
        deviceMetrics: {
          Mobile: 65,
          Desktop: 28,
          Tablet: 7,
        },
      };
      setAnalyticsData(mockData);
    } catch (error) {
      console.log('Error loading analytics:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadAnalytics();
    setIsRefreshing(false);
  };

  if (isLoading || !analyticsData) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </View>
    );
  }

  const openRate = analyticsData.campaignMetrics.opened / analyticsData.campaignMetrics.sent;
  const clickRate = analyticsData.campaignMetrics.clicked / analyticsData.campaignMetrics.sent;

  const chartConfig = {
    backgroundColor: colors.surface,
    backgroundGradientFrom: colors.surface,
    backgroundGradientTo: colors.surface,
    color: () => colors.primary,
    strokeWidth: 2,
    barPercentage: 0.5,
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
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
        <View style={[styles.header, { paddingTop: insets.top }]}>
          <View>
            <StyledText style={[styles.headerTitle, { color: colors.text }]}>
              Analytics
            </StyledText>
            <StyledText style={[styles.headerSubtitle, { color: colors.textSecondary }]}>
              Campaign performance overview
            </StyledText>
          </View>
        </View>

        {/* Period Selector */}
        <View style={styles.periodSelector}>
          {(['week', 'month', 'year'] as const).map((p) => (
            <TouchableOpacity
              key={p}
              style={[
                styles.periodButton,
                {
                  backgroundColor: period === p ? colors.primary : colors.surface,
                  borderColor: colors.border,
                },
              ]}
              onPress={() => setPeriod(p)}
            >
              <StyledText
                style={[
                  styles.periodText,
                  {
                    color: period === p ? '#fff' : colors.text,
                  },
                ]}
              >
                {p.charAt(0).toUpperCase() + p.slice(1)}
              </StyledText>
            </TouchableOpacity>
          ))}
        </View>

        {/* Key Metrics */}
        <View style={styles.metricsGrid}>
          <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <Send size={24} color={colors.primary} />
            <StyledText style={[styles.metricValue, { color: colors.text }]}>
              {(analyticsData.campaignMetrics.sent / 1000).toFixed(1)}k
            </StyledText>
            <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Sent
            </StyledText>
          </View>

          <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <MailOpen size={24} color={colors.success} />
            <StyledText style={[styles.metricValue, { color: colors.text }]}>
              {formatPercentage(openRate)}
            </StyledText>
            <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Open Rate
            </StyledText>
          </View>

          <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <MousePointerClick size={24} color={colors.info} />
            <StyledText style={[styles.metricValue, { color: colors.text }]}>
              {formatPercentage(clickRate)}
            </StyledText>
            <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Click Rate
            </StyledText>
          </View>

          <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <AlertCircle size={24} color={colors.error} />
            <StyledText style={[styles.metricValue, { color: colors.text }]}>
              {analyticsData.campaignMetrics.bounced}
            </StyledText>
            <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Bounces
            </StyledText>
          </View>
        </View>

        {/* Line Chart - Daily Trends */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
            Daily Activity Trend
          </StyledText>
          <LineChart
            data={{
              labels: analyticsData.dailyMetrics.map((m) => m.date),
              datasets: [
                {
                  data: analyticsData.dailyMetrics.map((m) => m.sends),
                  color: () => colors.primary,
                  strokeWidth: 2,
                },
              ],
            }}
            width={340}
            height={220}
            chartConfig={chartConfig}
            style={styles.chart}
            bezier
          />
        </View>

        {/* Bar Chart - Opens vs Clicks */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
            Opens & Clicks Comparison
          </StyledText>
          <BarChart
            data={{
              labels: analyticsData.dailyMetrics.slice(0, 5).map((m) => m.date),
              datasets: [
                {
                  data: analyticsData.dailyMetrics.slice(0, 5).map((m) => m.opens),
                  color: () => colors.success,
                },
                {
                  data: analyticsData.dailyMetrics.slice(0, 5).map((m) => m.clicks),
                  color: () => colors.info,
                },
              ],
            }}
            width={340}
            height={220}
            chartConfig={chartConfig}
            style={styles.chart}
            yAxisLabel=""
            yAxisSuffix=""
          />
        </View>

        {/* Pie Chart - Device Breakdown */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
            Device Breakdown
          </StyledText>
          <PieChart
            data={[
              {
                name: 'Mobile',
                population: analyticsData.deviceMetrics.Mobile,
                color: colors.primary,
                legendFontColor: colors.text,
              },
              {
                name: 'Desktop',
                population: analyticsData.deviceMetrics.Desktop,
                color: colors.success,
                legendFontColor: colors.text,
              },
              {
                name: 'Tablet',
                population: analyticsData.deviceMetrics.Tablet,
                color: colors.info,
                legendFontColor: colors.text,
              },
            ]}
            width={340}
            height={220}
            chartConfig={chartConfig}
            accessor="population"
            backgroundColor="transparent"
            paddingLeft="15"
            style={styles.chart}
          />
        </View>

        {/* Top Campaigns */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
            Top Performing Campaigns
          </StyledText>
          {analyticsData.topCampaigns.map((campaign, index) => (
            <View
              key={index}
              style={[styles.campaignRow, { borderBottomColor: colors.border }]}
            >
              <StyledText style={[styles.campaignName, { color: colors.text }]}>
                {campaign.name}
              </StyledText>
              <View style={styles.campaignStats}>
                <StyledText style={[styles.stat, { color: colors.textSecondary }]}>
                  {formatPercentage(campaign.openRate)} opens
                </StyledText>
                <StyledText style={[styles.stat, { color: colors.textSecondary }]}>
                  {formatPercentage(campaign.clickRate)} clicks
                </StyledText>
              </View>
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
    marginBottom: 24,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    marginBottom: 4,
  },
  headerSubtitle: {
    fontSize: 14,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  periodSelector: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 24,
  },
  periodButton: {
    flex: 1,
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 8,
    borderWidth: 1,
    alignItems: 'center',
  },
  periodText: {
    fontWeight: '600',
    fontSize: 13,
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginBottom: 24,
  },
  metricCard: {
    width: '48%',
    paddingHorizontal: 12,
    paddingVertical: 16,
    borderRadius: 8,
    borderWidth: 1,
    alignItems: 'center',
  },
  metricValue: {
    fontSize: 18,
    fontWeight: '700',
    marginTop: 8,
    marginBottom: 4,
  },
  metricLabel: {
    fontSize: 12,
    textAlign: 'center',
  },
  section: {
    marginBottom: 28,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 12,
  },
  chart: {
    borderRadius: 8,
  },
  campaignRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  campaignName: {
    fontSize: 14,
    fontWeight: '600',
    flex: 1,
  },
  campaignStats: {
    alignItems: 'flex-end',
  },
  stat: {
    fontSize: 12,
  },
});
