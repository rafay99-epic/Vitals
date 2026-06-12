import { LegalLayout, Section, P, List, Item, Strong, ExtLink } from './LegalLayout'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL } from '../lib/links'

export default function Terms() {
  return (
    <LegalLayout title="Terms & Conditions" updated="June 12, 2026">
      <Section title="1. Agreement to these terms">
        <P>
          These Terms &amp; Conditions ("Terms") govern your use of the <Strong>Vitals</Strong> macOS application (the "App"), its
          fan-control helper, its update service, and this website (together, the "Services"). The Services are operated by{' '}
          <Strong>{COMPANY}</Strong> ("we", "us", "our") and developed by{' '}
          <ExtLink href={DEVELOPER_URL}>{DEVELOPER} — rafay99.com</ExtLink>.
        </P>
        <P>
          By downloading, installing, or using the App, or by browsing this website, you agree to be bound by these Terms. If you do
          not agree, do not install or use the Services. If you are using the Services on behalf of an organization, you represent
          that you have authority to bind that organization to these Terms.
        </P>
      </Section>

      <Section title="2. What Vitals is">
        <P>
          Vitals is a hardware-monitoring utility for Apple Silicon Macs. It reads temperature sensors, fan speeds, CPU usage,
          memory statistics, battery condition, and related system information, and displays them in a dashboard and the macOS menu
          bar. It can optionally log readings to a CSV file on your machine and, where you explicitly enable it, control fan speeds
          within manufacturer-rated ranges.
        </P>
        <P>
          The App is provided <Strong>free of charge</Strong> and is <Strong>free software</Strong>: its source code is publicly
          available at <ExtLink href={REPO_URL}>github.com/rafay99-epic/Vitals</ExtLink> under the{' '}
          <ExtLink href={`${REPO_URL}/blob/main/LICENSE`}>GNU General Public License v3.0</ExtLink>, which grants you the right to
          use, study, modify, and redistribute it under the same terms. These Terms govern your use of the distributed application
          and this website, alongside — never in place of — the rights the GPL gives you.
        </P>
        <P>
          The Applications &amp; Cleanup feature is informed by the{' '}
          <ExtLink href="https://github.com/tw93/mole">Mole</ExtLink> project (GPL-3.0), whose catalog of app-leftover locations
          and safety-first uninstall design shaped Vitals' implementation — full credit to its authors.
        </P>
      </Section>

      <Section title="3. Hardware control — assumption of risk">
        <P>
          <Strong>Read this section carefully.</Strong> Vitals includes an optional fan-control feature that writes to your Mac's
          System Management Controller (SMC). Although the App applies multiple safety measures — values are clamped to the
          manufacturer's rated RPM range, changes require administrator authorization, and macOS's own thermal protection remains
          active underneath at all times — controlling cooling hardware is inherently your decision and carries inherent risk.
        </P>
        <List>
          <Item>
            You acknowledge that running a fan slower or faster than macOS would choose can affect component temperatures,
            performance (thermal throttling), acoustics, energy use, and component wear.
          </Item>
          <Item>
            You enable and use fan control <Strong>entirely at your own risk</Strong>. To the maximum extent permitted by law, we
            accept no liability for hardware damage, data loss, reduced component lifespan, voided warranties, or any other harm
            arising from your use of fan control or any other feature of the App.
          </Item>
          <Item>
            If you are unsure, leave fan control disabled or set to "Auto" — the App then never writes to your hardware and macOS
            retains full control of cooling.
          </Item>
        </List>
      </Section>

      <Section title="4. Administrator access and the helper daemon">
        <P>
          Enabling fan control installs a small privileged helper (a launchd daemon) that requires your administrator password once
          at installation. The helper exists solely to apply your chosen fan settings and to restore automatic control; it performs
          no other function, communicates only with your local machine, and can be removed at any time from within the App
          ("Disable…"), which also restores macOS automatic fan control.
        </P>
        <P>
          You are responsible for ensuring you are authorized to install software requiring administrator privileges on the machine
          in question.
        </P>
      </Section>

      <Section title="5. Updates">
        <P>
          The App can check GitHub Releases for newer versions and, with your action or where automatic checks are enabled, download
          and install updates. Updates may change, add, or remove functionality. You can disable automatic update checks in the
          App's settings. We are under no obligation to provide updates, maintenance, or support.
        </P>
      </Section>

      <Section title="6. Acceptable use">
        <List>
          <Item>You may not use the Services for any unlawful purpose or in violation of any applicable regulation.</Item>
          <Item>
            You may not misrepresent the origin of the App, remove or alter copyright and attribution notices, or distribute
            modified builds under the Vitals name in a way that implies they are official releases.
          </Item>
          <Item>
            You may not use the website or its infrastructure in a manner that disrupts it for others (scraping at abusive rates,
            attempting to breach security, and similar conduct).
          </Item>
        </List>
      </Section>

      <Section title="7. Intellectual property">
        <P>
          The Vitals name, logo, website design, and application design are the property of {COMPANY}. The publication of source
          code does not grant any right to use our names or marks except as needed for truthful attribution. All third-party marks
          (including Apple, macOS, and GitHub) belong to their respective owners; Vitals is an independent project and is not
          affiliated with, endorsed by, or sponsored by Apple Inc. or GitHub, Inc.
        </P>
      </Section>

      <Section title="8. Third-party services">
        <P>
          Downloads and update checks are served through GitHub Releases, and this website queries the GitHub API to display the
          latest version. Your use of GitHub is subject to{' '}
          <ExtLink href="https://docs.github.com/en/site-policy/github-terms/github-terms-of-service">GitHub's Terms of Service</ExtLink>.
          We are not responsible for the availability or conduct of third-party services.
        </P>
      </Section>

      <Section title="9. Disclaimer of warranties">
        <P>
          THE SERVICES ARE PROVIDED <Strong>"AS IS" AND "AS AVAILABLE"</Strong>, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
          INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, ACCURACY, AND
          NON-INFRINGEMENT. WE DO NOT WARRANT THAT SENSOR READINGS ARE ERROR-FREE, THAT THE APP WILL BE UNINTERRUPTED OR FREE OF
          DEFECTS, OR THAT IT IS SUITABLE FOR ANY SAFETY-CRITICAL PURPOSE. VITALS IS A MONITORING CONVENIENCE, NOT A DIAGNOSTIC OR
          PROTECTIVE SYSTEM — DO NOT RELY ON IT TO PREVENT HARDWARE DAMAGE.
        </P>
      </Section>

      <Section title="10. Limitation of liability">
        <P>
          TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL {COMPANY.toUpperCase()}, ITS DEVELOPER, OR
          CONTRIBUTORS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES — INCLUDING
          HARDWARE DAMAGE, DATA LOSS, LOST PROFITS, OR BUSINESS INTERRUPTION — ARISING OUT OF OR RELATING TO THE SERVICES, EVEN IF
          ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. BECAUSE THE SERVICES ARE PROVIDED FREE OF CHARGE, OUR TOTAL AGGREGATE
          LIABILITY FOR ALL CLAIMS SHALL NOT EXCEED ZERO (0), OR WHERE A JURISDICTION DOES NOT PERMIT SUCH A LIMIT, THE SMALLEST
          AMOUNT THAT JURISDICTION PERMITS.
        </P>
        <P>
          Some jurisdictions do not allow the exclusion of certain warranties or limitations of liability; in those jurisdictions,
          the above limitations apply to the fullest extent permitted.
        </P>
      </Section>

      <Section title="11. Indemnification">
        <P>
          You agree to indemnify and hold harmless {COMPANY} and its developer from any claims, damages, liabilities, and expenses
          (including reasonable legal fees) arising from your misuse of the Services, your violation of these Terms, or your
          violation of any rights of a third party.
        </P>
      </Section>

      <Section title="12. Termination">
        <P>
          You may stop using the Services at any time by uninstalling the App (and removing the fan-control helper from within the
          App first, which restores automatic cooling). We may discontinue the Services, or any part of them, at any time without
          notice. Sections 3, 7, and 9–11 survive termination.
        </P>
      </Section>

      <Section title="13. Changes to these terms">
        <P>
          We may revise these Terms from time to time. The "Last updated" date at the top reflects the latest revision, and the
          current version is always available on this page. Continued use of the Services after changes take effect constitutes
          acceptance of the revised Terms.
        </P>
      </Section>

      <Section title="14. Governing law">
        <P>
          These Terms are governed by the laws of the jurisdiction in which {COMPANY} is established, without regard to
          conflict-of-law principles. Any dispute shall be brought exclusively in the courts of that jurisdiction.
        </P>
      </Section>

      <Section title="15. Contact">
        <P>
          Questions about these Terms can be raised via <ExtLink href={DEVELOPER_URL}>rafay99.com</ExtLink> or by opening an issue
          on the <ExtLink href={REPO_URL}>GitHub repository</ExtLink>.
        </P>
      </Section>
    </LegalLayout>
  )
}
