import { LegalLayout, Section, P, List, Item, Strong, ExtLink } from './LegalLayout'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL } from '../lib/links'

export default function Privacy() {
  return (
    <LegalLayout title="Privacy Policy" updated="June 12, 2026">
      <Section title="The short version">
        <P>
          <Strong>Vitals does not collect, store, transmit, or sell any of your personal data. We run no servers, no analytics, no
          telemetry, no crash reporting, and no accounts.</Strong> Everything the App measures stays on your Mac. The only network
          requests the App or this website ever make are to GitHub, to check for and download releases — and those requests carry
          no personal information beyond what any web request inherently includes.
        </P>
        <P>
          The rest of this policy spells that out in detail. It is issued by <Strong>{COMPANY}</Strong>, developer of Vitals
          (<ExtLink href={DEVELOPER_URL}>{DEVELOPER} — rafay99.com</ExtLink>), and covers both the Vitals macOS application (the
          "App") and this website.
        </P>
      </Section>

      <Section title="1. Data the App reads — and where it stays">
        <P>The App reads the following from your Mac, locally, to display it to you:</P>
        <List>
          <Item>Temperature sensors (CPU, GPU, SSD, battery) via the IOKit HID interface</Item>
          <Item>Fan speeds and fan configuration via the System Management Controller (SMC)</Item>
          <Item>CPU utilization, per-process CPU usage, and process names from the operating system</Item>
          <Item>Memory statistics (usage, swap, memory pressure) from the kernel</Item>
          <Item>Battery charge, health, cycle count, and power flow from the battery controller</Item>
        </List>
        <P>
          <Strong>None of this leaves your machine.</Strong> Readings exist in the App's memory while it runs. If you enable
          logging, readings are appended to a CSV file stored at{' '}
          <Strong>~/Library/Application Support/Vitals/history.csv</Strong> on your Mac — a file you can open, export, or delete at
          any time. The App never uploads this file anywhere.
        </P>
      </Section>

      <Section title="2. Settings stored on your device">
        <P>
          Your preferences (refresh interval, temperature unit, theme, alert thresholds, and similar) are stored in macOS user
          defaults on your machine. If you enable fan control, your chosen fan settings are written to{' '}
          <Strong>/Library/Application Support/Vitals/fan-state.json</Strong> so the helper can apply them. Both are local files
          under your control and are removed when you uninstall the App and its helper.
        </P>
      </Section>

      <Section title="3. Network requests the App makes">
        <P>The App contacts the network in exactly one scenario: software updates.</P>
        <List>
          <Item>
            <Strong>Update checks</Strong> — when enabled (you can turn this off in Settings), the App periodically asks the GitHub
            API whether a newer release exists. This request goes directly from your Mac to GitHub.
          </Item>
          <Item>
            <Strong>Update downloads</Strong> — when you choose to install an update, the App downloads the new DMG from GitHub
            Releases.
          </Item>
        </List>
        <P>
          Like any web request, these expose your IP address and basic request metadata to the receiving server — in this case
          GitHub, not us. We never see these requests, and they contain no identifier tied to you: no device ID, no account, no
          fingerprint. GitHub's handling of such requests is described in the{' '}
          <ExtLink href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">
            GitHub Privacy Statement
          </ExtLink>
          . There is no other network activity in the App — no telemetry, no usage analytics, no crash reporters, no advertising
          SDKs, and no third-party frameworks that phone home.
        </P>
      </Section>

      <Section title="4. Notifications">
        <P>
          If you enable overheat or thermal-pressure alerts, notifications are generated and delivered locally by macOS. No
          notification content is sent to us or any third party.
        </P>
      </Section>

      <Section title="5. This website">
        <P>The website you are reading is a static page. It sets <Strong>no cookies</Strong>, runs <Strong>no analytics or tracking
        scripts</Strong>, embeds no advertising, and uses no fingerprinting.</P>
        <List>
          <Item>
            Your browser requests the page from our hosting provider, which (like all web hosts) may keep standard server logs —
            IP address, user agent, requested URL, timestamp — for security and operational purposes under its own policy.
          </Item>
          <Item>
            The page queries the GitHub API from your browser to display the latest release version and download size, and the
            download buttons link to GitHub Releases. Those requests are made by your browser directly to GitHub and are covered by
            the GitHub Privacy Statement linked above.
          </Item>
        </List>
      </Section>

      <Section title="6. What we never do">
        <List>
          <Item>We do not collect, buy, sell, rent, share, or trade personal data — we have none to begin with.</Item>
          <Item>We do not profile you, advertise to you, or track you across apps or websites.</Item>
          <Item>We do not use your hardware readings for any purpose; they never reach us.</Item>
          <Item>We hold no user database, so there is nothing to breach, subpoena, or leak on our side.</Item>
        </List>
      </Section>

      <Section title="7. Data retention">
        <P>
          We retain nothing, because nothing is transmitted to us. The only persistent data the App creates — the optional CSV log
          and your settings — lives on your Mac and is yours to delete. Uninstalling the App and removing the helper deletes the
          App's presence from your system; the CSV log remains until you delete it, since it is your data.
        </P>
      </Section>

      <Section title="8. Your rights (GDPR, CCPA, and similar laws)">
        <P>
          Privacy laws such as the EU/UK GDPR and the California CCPA/CPRA grant rights to access, correct, delete, and port
          personal data, and to object to or restrict its processing. Because we process no personal data, there is nothing for us
          to access, correct, delete, or port — these rights are satisfied by design. If you believe we hold any personal data about
          you, contact us via the channels below and we will respond; you also retain the right to lodge a complaint with your
          local supervisory authority.
        </P>
      </Section>

      <Section title="9. Children's privacy">
        <P>
          The Services are not directed at children and collect no data from anyone, children included. We are not aware of any way
          the Services could accumulate children's personal information.
        </P>
      </Section>

      <Section title="10. Security">
        <P>
          Because your data never leaves your Mac, its security is governed by your machine's own protections (FileVault, macOS
          permissions, your user account). The fan-control helper is installed with root ownership and accepts state only from a
          file in a protected location. Update downloads come exclusively from GitHub Releases over HTTPS.
        </P>
      </Section>

      <Section title="11. Changes to this policy">
        <P>
          If the App's behavior ever changes in a way that affects privacy — for example, if a future version added an opt-in
          crash reporter — this policy will be updated before that change ships, the "Last updated" date will change, and the
          change will be noted in the release notes. The current policy is always available at this address.
        </P>
      </Section>

      <Section title="12. Contact">
        <P>
          Privacy questions can be raised via <ExtLink href={DEVELOPER_URL}>rafay99.com</ExtLink> or by opening an issue on the{' '}
          <ExtLink href={REPO_URL}>GitHub repository</ExtLink>.
        </P>
      </Section>
    </LegalLayout>
  )
}
