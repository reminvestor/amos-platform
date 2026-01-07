import React from 'react';
import { ScrollView, View, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';

export default function PrivacyPolicyScreen() {
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

      <StyledText style={[styles.lead, { color: colors.text }]}>
        At AMOS Labs, we take your privacy seriously. This Privacy Policy explains how we collect,
        use, disclose, and safeguard your information when you use our Service.
      </StyledText>

      <Section title="1. Information We Collect" colors={colors}>
        <SubSection title="Personal Information" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            We collect information that you provide directly to us, including:
          </StyledText>
          <BulletList
            items={[
              'Name and email address',
              'Business name and information',
              'Payment and billing information',
              'Profile information and preferences',
              'Communications with us',
            ]}
            colors={colors}
          />
        </SubSection>

        <SubSection title="Usage Information" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            We automatically collect certain information about your use of the Service:
          </StyledText>
          <BulletList
            items={[
              'Log data (IP address, browser type, pages visited)',
              'Device information',
              'Usage patterns and preferences',
              'Campaign and analytics data',
              'AI conversation history',
            ]}
            colors={colors}
          />
        </SubSection>

        <SubSection title="Content You Create" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            We store content you create using our Service, including:
          </StyledText>
          <BulletList
            items={[
              'Email campaigns and templates',
              'Landing pages and marketing materials',
              'Contact lists and customer data',
              'Documents and files you upload',
              'AI-generated content',
            ]}
            colors={colors}
          />
        </SubSection>
      </Section>

      <Section title="2. How We Use Your Information" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We use the information we collect to:
        </StyledText>
        <BulletList
          items={[
            'Provide, maintain, and improve our Service',
            'Process transactions and send related information',
            'Send you technical notices and support messages',
            'Respond to your comments and questions',
            'Generate AI-powered recommendations and content',
            'Monitor and analyze trends, usage, and activities',
            'Detect and prevent fraud and abuse',
            'Comply with legal obligations',
          ]}
          colors={colors}
        />
      </Section>

      <Section title="3. AI and Machine Learning" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We use artificial intelligence and machine learning to provide our Service. This includes:
        </StyledText>
        <BulletList
          items={[
            'Processing your conversations with our AI assistant',
            'Generating marketing content based on your inputs',
            'Analyzing campaign performance',
            'Providing personalized recommendations',
          ]}
          colors={colors}
        />
        <StyledText style={[styles.important, { color: colors.text }]}>
          Important: We use AWS Bedrock (Claude) for AI capabilities. Your data is processed
          according to AWS's privacy policies. We do not train AI models on your confidential
          business data without your explicit consent.
        </StyledText>
      </Section>

      <Section title="4. Information Sharing and Disclosure" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We may share your information in the following circumstances:
        </StyledText>

        <SubSection title="With Your Consent" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            We may share your information with third parties when you explicitly authorize us to do so.
          </StyledText>
        </SubSection>

        <SubSection title="Service Providers" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            We share information with third-party service providers who perform services on our behalf:
          </StyledText>
          <BulletList
            items={[
              'AWS (hosting and AI services)',
              'Stripe (payment processing)',
              'Mailgun (email delivery)',
              'Other integrations you connect (HubSpot, Twilio, etc.)',
            ]}
            colors={colors}
          />
        </SubSection>

        <SubSection title="Legal Requirements" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            We may disclose your information if required by law or in response to valid requests by
            public authorities.
          </StyledText>
        </SubSection>

        <SubSection title="Business Transfers" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            If AMOS Labs is involved in a merger, acquisition, or sale of assets, your information
            may be transferred as part of that transaction.
          </StyledText>
        </SubSection>
      </Section>

      <Section title="5. Data Security" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We implement appropriate technical and organizational measures to protect your information:
        </StyledText>
        <BulletList
          items={[
            'Encryption in transit (HTTPS/TLS)',
            'Encryption at rest for sensitive data',
            'Regular security assessments',
            'Access controls and authentication',
            'Secure data centers (AWS)',
          ]}
          colors={colors}
        />
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          However, no method of transmission over the Internet or electronic storage is 100% secure.
          We cannot guarantee absolute security.
        </StyledText>
      </Section>

      <Section title="6. Data Retention" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We retain your information for as long as your account is active or as needed to provide
          you services. We will also retain and use your information as necessary to:
        </StyledText>
        <BulletList
          items={[
            'Comply with legal obligations',
            'Resolve disputes',
            'Enforce our agreements',
          ]}
          colors={colors}
        />
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          You can request deletion of your data by contacting us. Some information may be retained
          in backups for a limited time.
        </StyledText>
      </Section>

      <Section title="7. Your Rights and Choices" colors={colors}>
        <SubSection title="Access and Update" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            You can access and update your account information through your account settings.
          </StyledText>
        </SubSection>

        <SubSection title="Delete Your Account" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            You may delete your account at any time. This will permanently delete your data from our
            active systems.
          </StyledText>
        </SubSection>

        <SubSection title="Opt-Out" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            You can opt out of receiving promotional emails by following the unsubscribe instructions
            in those emails.
          </StyledText>
        </SubSection>

        <SubSection title="Data Portability" colors={colors}>
          <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
            You can export your data at any time through your account settings.
          </StyledText>
        </SubSection>
      </Section>

      <Section title="8. Cookies and Tracking" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We use cookies and similar tracking technologies to:
        </StyledText>
        <BulletList
          items={[
            'Keep you logged in',
            'Remember your preferences',
            'Understand how you use our Service',
            'Improve our Service',
          ]}
          colors={colors}
        />
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          You can control cookies through your browser settings.
        </StyledText>
      </Section>

      <Section title="9. Third-Party Links" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          Our Service may contain links to third-party websites. We are not responsible for the
          privacy practices of these external sites. We encourage you to review their privacy policies.
        </StyledText>
      </Section>

      <Section title="10. Children's Privacy" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          Our Service is not intended for children under 13 years of age. We do not knowingly collect
          personal information from children under 13. If you become aware that a child has provided
          us with personal information, please contact us.
        </StyledText>
      </Section>

      <Section title="11. International Data Transfers" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          Your information may be transferred to and processed in countries other than your own. We
          ensure appropriate safeguards are in place to protect your information in accordance with
          this Privacy Policy.
        </StyledText>
      </Section>

      <Section title="12. GDPR Compliance (EU Users)" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          If you are located in the European Economic Area (EEA), you have additional rights under GDPR:
        </StyledText>
        <BulletList
          items={[
            'Right to access your personal data',
            'Right to rectification of inaccurate data',
            'Right to erasure ("right to be forgotten")',
            'Right to restrict processing',
            'Right to data portability',
            'Right to object to processing',
          ]}
          colors={colors}
        />
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          To exercise these rights, please contact us at privacy@amoslabs.com.
        </StyledText>
      </Section>

      <Section title="13. CCPA Compliance (California Residents)" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          California residents have specific rights regarding their personal information:
        </StyledText>
        <BulletList
          items={[
            'Right to know what personal information is collected',
            'Right to know if personal information is sold or disclosed',
            'Right to opt-out of the sale of personal information',
            'Right to deletion of personal information',
            'Right to non-discrimination for exercising CCPA rights',
          ]}
          colors={colors}
        />
        <StyledText style={[styles.important, { color: colors.text }]}>
          Note: We do not sell your personal information.
        </StyledText>
      </Section>

      <Section title="14. Changes to This Privacy Policy" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          We may update this Privacy Policy from time to time. We will notify you of any material
          changes by posting the new Privacy Policy on this page and updating the "Last updated" date.
        </StyledText>
      </Section>

      <Section title="15. Contact Us" colors={colors}>
        <StyledText style={[styles.paragraph, { color: colors.textSecondary }]}>
          If you have any questions about this Privacy Policy, please contact us:
        </StyledText>
        <StyledText style={[styles.contactInfo, { color: colors.text }]}>
          AMOS Labs{'\n'}
          Email: privacy@amoslabs.com{'\n'}
          Support: support@amoslabs.com
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

interface SubSectionProps {
  title: string;
  colors: ReturnType<typeof getColors>;
  children: React.ReactNode;
}

function SubSection({ title, colors, children }: SubSectionProps) {
  return (
    <View style={styles.subSection}>
      <StyledText style={[styles.subSectionTitle, { color: colors.text }]}>{title}</StyledText>
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
    marginBottom: 16,
    textAlign: 'center',
  },
  lead: {
    fontSize: 16,
    lineHeight: 26,
    marginBottom: 24,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 12,
  },
  subSection: {
    marginTop: 16,
  },
  subSectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  paragraph: {
    fontSize: 15,
    lineHeight: 24,
    marginBottom: 12,
  },
  important: {
    fontSize: 15,
    lineHeight: 24,
    marginTop: 12,
    fontWeight: '500',
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
