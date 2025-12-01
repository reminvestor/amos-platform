import React from 'react';
import { ScrollView, View, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';

export default function TermsScreen() {
  const insets = useSafeAreaInsets();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const lastUpdated = new Date().toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: colors.background }]}
      contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 32 }]}
      showsVerticalScrollIndicator={false}
    >
      <StyledText style={[styles.lastUpdated, { color: colors.textSecondary }]}>
        Last updated: {lastUpdated}
      </StyledText>

      <Section title="1. Acceptance of Terms" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          By accessing and using AMOS Labs ("Service"), you accept and agree to be bound by the terms
          and provision of this agreement. If you do not agree to these Terms of Service, please do
          not use our Service.
        </StyledText>
      </Section>

      <Section title="2. Description of Service" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          AMOS Labs provides an AI-powered business automation platform that helps users manage
          marketing campaigns, create landing pages, automate workflows, and integrate with various
          third-party services.
        </StyledText>
      </Section>

      <Section title="3. User Accounts" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          To access certain features of the Service, you must create an account. You agree to:
        </StyledText>
        <BulletList
          items={[
            'Provide accurate, current, and complete information during registration',
            'Maintain the security of your password and account',
            'Notify us immediately of any unauthorized use of your account',
            'Accept responsibility for all activities that occur under your account',
          ]}
          colors={colors}
        />
      </Section>

      <Section title="4. Acceptable Use" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          You agree not to use the Service to:
        </StyledText>
        <BulletList
          items={[
            'Violate any applicable laws or regulations',
            'Infringe on intellectual property rights of others',
            'Transmit spam, malware, or malicious code',
            'Harass, abuse, or harm other users',
            'Attempt to gain unauthorized access to our systems',
            'Use the Service for any illegal or unauthorized purpose',
          ]}
          colors={colors}
        />
      </Section>

      <Section title="5. Subscription and Payment" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          Some features of the Service require a paid subscription. By subscribing, you agree to:
        </StyledText>
        <BulletList
          items={[
            'Pay all fees associated with your subscription plan',
            'Provide accurate billing information',
            'Allow automatic renewal unless you cancel your subscription',
            'Understand that fees are non-refundable except as required by law',
          ]}
          colors={colors}
        />
      </Section>

      <Section title="6. Intellectual Property" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          The Service and its original content, features, and functionality are owned by AMOS Labs
          and are protected by international copyright, trademark, patent, trade secret, and other
          intellectual property laws.
        </StyledText>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          You retain ownership of any content you create using the Service. By using the Service,
          you grant us a license to use, store, and display your content solely for the purpose of
          providing the Service.
        </StyledText>
      </Section>

      <Section title="7. Third-Party Integrations" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          The Service may integrate with third-party services (such as Stripe, Mailgun, HubSpot,
          etc.). Your use of these integrations is subject to the respective third-party terms of
          service and privacy policies.
        </StyledText>
      </Section>

      <Section title="8. AI-Generated Content" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          Our Service uses artificial intelligence to generate content. While we strive for accuracy
          and quality:
        </StyledText>
        <BulletList
          items={[
            'AI-generated content may contain errors or inaccuracies',
            'You are responsible for reviewing and approving all content before use',
            'We do not guarantee the accuracy, completeness, or suitability of AI-generated content',
            'You should verify important information independently',
          ]}
          colors={colors}
        />
      </Section>

      <Section title="9. Data and Privacy" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          Your use of the Service is also governed by our Privacy Policy. Please review our Privacy
          Policy to understand how we collect, use, and protect your data.
        </StyledText>
      </Section>

      <Section title="10. Termination" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We may terminate or suspend your account and access to the Service immediately, without
          prior notice or liability, for any reason, including if you breach these Terms. Upon
          termination, your right to use the Service will immediately cease.
        </StyledText>
      </Section>

      <Section title="11. Limitation of Liability" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          To the maximum extent permitted by law, AMOS Labs shall not be liable for any indirect,
          incidental, special, consequential, or punitive damages, or any loss of profits or
          revenues, whether incurred directly or indirectly, or any loss of data, use, goodwill, or
          other intangible losses resulting from:
        </StyledText>
        <BulletList
          items={[
            'Your use or inability to use the Service',
            'Any unauthorized access to or use of our servers and/or any personal information stored therein',
            'Any bugs, viruses, or malicious code transmitted through the Service',
            'Any errors or omissions in any content or for any loss or damage incurred as a result of your use of any content',
          ]}
          colors={colors}
        />
      </Section>

      <Section title="12. Disclaimer" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          The Service is provided on an "AS IS" and "AS AVAILABLE" basis. AMOS Labs makes no
          warranties, expressed or implied, and hereby disclaims all warranties including, without
          limitation, implied warranties or conditions of merchantability, fitness for a particular
          purpose, or non-infringement of intellectual property.
        </StyledText>
      </Section>

      <Section title="13. Changes to Terms" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We reserve the right to modify or replace these Terms at any time. If a revision is
          material, we will provide at least 30 days' notice prior to any new terms taking effect.
          What constitutes a material change will be determined at our sole discretion.
        </StyledText>
      </Section>

      <Section title="14. Governing Law" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          These Terms shall be governed by and construed in accordance with the laws of the United
          States, without regard to its conflict of law provisions.
        </StyledText>
      </Section>

      <Section title="15. Contact Us" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          If you have any questions about these Terms, please contact us at:
        </StyledText>
        <StyledText style={[styles.contactInfo, { color: colors.text }]}>
          AMOS Labs{'\n'}
          Email: support@amoslabs.com
        </StyledText>
      </Section>
    </ScrollView>
  );
}

interface SectionProps {
  title: string;
  colors: ReturnType<typeof getColors>;
  children: React.ReactNode;
}

function Section({ title, colors, children }: SectionProps) {
  return (
    <View style={styles.section}>
      <StyledText style={[styles.sectionTitle, { color: colors.text }]}>{title}</StyledText>
      {children}
    </View>
  );
}

interface BulletListProps {
  items: string[];
  colors: ReturnType<typeof getColors>;
}

function BulletList({ items, colors }: BulletListProps) {
  return (
    <View style={styles.bulletList}>
      {items.map((item, index) => (
        <View key={index} style={styles.bulletItem}>
          <StyledText style={[styles.bullet, { color: colors.primary }]}>{'\u2022'}</StyledText>
          <StyledText style={[styles.bulletText, { color: colors.textSecondary }]}>{item}</StyledText>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 16,
  },
  lastUpdated: {
    fontSize: 14,
    marginBottom: 24,
    textAlign: 'center',
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 12,
  },
  paragraph: {
    fontSize: 15,
    lineHeight: 24,
    marginBottom: 12,
  },
  bulletList: {
    marginTop: 8,
  },
  bulletItem: {
    flexDirection: 'row',
    marginBottom: 8,
    paddingRight: 16,
  },
  bullet: {
    fontSize: 15,
    lineHeight: 24,
    marginRight: 8,
  },
  bulletText: {
    fontSize: 15,
    lineHeight: 24,
    flex: 1,
  },
  contactInfo: {
    fontSize: 15,
    lineHeight: 24,
    fontWeight: '500',
  },
});
