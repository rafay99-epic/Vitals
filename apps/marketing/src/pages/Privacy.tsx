import { LegalLayout, Section, P, List, Item, Strong, ExtLink } from './LegalLayout'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL, SUPPORT_EMAIL } from '../lib/links'
import { useTitle } from '../lib/useTitle'

export default function Privacy() {
  useTitle('Privacy Policy — Vitals')
  return (
    <LegalLayout title="Privacy Policy" updated="October 23, 2026">
      <Section title="The short version">
        <P>
          <Strong>The Vitals app does not collect, store, transmit, or sell any of your personal data. It has no analytics, no
          telemetry, no background or automatic crash reporting, and no accounts.</Strong> Everything the App measures, and the
          diagnostic logs it keeps to help you troubleshoot, stay on your Mac. The one exception is entirely in your hands: if you
          hit a bug, the App can open your email program with those logs so you can choose to send them to the developer yourself —
          nothing is transmitted unless you press Send. Its only automatic network requests go to GitHub, to check for and download
          releases. Remote access, which is off until you turn it on, sends readings only to devices you pair, over your own
          Wi-Fi or your own Tailscale network (section 7). The Vitals Remote phone app talks to your Mac the same way; its only
          other network requests check for app updates, send Google basic diagnostics from the Android QR scanner, and, if you
          turn on built-in Tailscale, go to Tailscale (section 8). This website is almost as quiet: it sets no cookies and does no cross-site tracking — its one measurement tool is
          Vercel Web Analytics, an anonymized, cookieless page counter described in section 9.
        </P>
        <P>
          The rest of this policy spells that out in detail. It is issued by <Strong>{COMPANY}</Strong>, developer of Vitals
          (<ExtLink href={DEVELOPER_URL}>{DEVELOPER} — rafay99.com</ExtLink>), and covers the Vitals macOS application (the
          "App"), the Vitals Remote phone app for Android and iOS (the "phone app"), and this website.
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
          <Strong>None of this leaves your machine</Strong>, unless you turn on Remote and pair a device (section 7). Readings
          exist in the App's memory while it runs, and a history of them is kept in a database at{' '}
          <Strong>~/.vitals/history/history.sqlite3</Strong> on your Mac. History is on by default and can be turned off in
          Settings; you can export it as CSV or delete it at any time. The App never uploads it anywhere.
        </P>
      </Section>

      <Section title="2. Diagnostic logs">
        <P>
          To help diagnose problems, the App keeps a developer diagnostic log at <Strong>~/.vitals/logs/vitals.log</Strong> on your Mac.
          You control how much it records (Off, Errors, Normal, or Verbose) in Settings → Developer, and you can read it in the
          App's Log Console or reveal the file in Finder. Unlike the readings log above, this records what the App's own code is
          doing — events, errors with their technical details, and, if the App ever crashes, a record of the crash so the problem
          can be understood. It can therefore contain <Strong>file paths from your Mac, which include your macOS username</Strong>.
        </P>
        <P>
          This log is <Strong>local and capped in size</Strong> (older entries roll off). It is never uploaded or transmitted
          automatically — it exists only on your machine and is yours to read or delete. It leaves your Mac only if you choose to
          send a problem report, described next.
        </P>
      </Section>

      <Section title="3. Problem reports — the one time data can leave your Mac">
        <P>
          The App includes a <Strong>"Report a Problem"</Strong> feature (Settings → Developer). When you use it, the App opens a
          pre-addressed message in your own email program and reveals your diagnostic log so you can attach it. You see exactly what
          is included, and <Strong>nothing is sent until you review it and press Send yourself</Strong> in your email program. The
          App has no server and sends nothing on its own.
        </P>
        <P>
          A report you choose to send goes by email to the developer, {DEVELOPER} (<Strong>{SUPPORT_EMAIL}</Strong>), and is used
          solely to investigate the issue you described. Because it is an ordinary email you send, you decide what it contains and to
          whom; you can edit or cancel it before sending. If your Mac has no email program set up, the App falls back to revealing
          the log and copying the report text so you can send it however you like — still entirely your choice.
        </P>
      </Section>

      <Section title="4. Settings stored on your device">
        <P>
          Your preferences (refresh interval, temperature unit, theme, alert thresholds, and similar) are stored in macOS user
          defaults on your machine and mirrored to a readable JSON file at <Strong>~/.vitals/config/config.json</Strong>, so your
          setup survives an update or reinstall. If you enable fan control, your chosen fan settings are written to{' '}
          <Strong>/Library/Application Support/Vitals/fan-state.json</Strong> so the helper can apply them. These are local files
          under your control and are removed when you uninstall the App and its helper.
        </P>
      </Section>

      <Section title="5. Network requests the App makes">
        <P>
          The App contacts the internet in one scenario: software updates. Remote access, if you turn it on, stays on your own
          Wi-Fi and your own Tailscale network and is covered separately in section 7.
        </P>
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

      <Section title="6. Notifications">
        <P>
          If you enable overheat or thermal-pressure alerts, notifications are generated and delivered locally by macOS. No
          notification content is sent to us or any third party.
        </P>
      </Section>

      <Section title="7. Remote access (off by default)">
        <P>
          If you turn on Remote in the App, a small gateway runs on your Mac. Phones and browsers you pair with a one-time code
          can then read your Mac's live readings and send the commands you allow. They reach it two ways, and neither is exposed
          to the public internet:
        </P>
        <List>
          <Item>
            <Strong>On your Wi-Fi:</Strong> the Mac announces itself on your local network (Bonjour) and accepts connections
            there. Every connection is encrypted end to end and pinned to your Mac's own key, so a device that is not paired, or a
            Mac pretending to be yours, cannot read anything. To be found, the Mac shows its computer name and its public key to
            other devices on the same network; readings and commands are never visible.
          </Item>
          <Item>
            <Strong>Over Tailscale:</Strong> the gateway is also published to your own Tailscale network with{' '}
            <Strong>tailscale serve</Strong>, so only your own Tailscale login can connect when you are away from home.
          </Item>
          <Item>
            <Strong>What travels:</Strong> the readings listed in section 1, process names and resource use, the list of running
            apps, and commands you send. This goes directly between your devices, encrypted; it never passes through our servers.
          </Item>
          <Item>
            <Strong>What is stored on your Mac:</Strong> paired devices, hashed session tokens, the command history, and an activity
            log of connections, requests and events, in <Strong>~/.vitals/remote/</Strong>. Old entries are pruned automatically
            (frames after 3 days, events after 30). You can read this log in Vitals under Remote, Activity.
          </Item>
          <Item>
            <Strong>What the phone app stores:</Strong> the Mac's address and key, the Tailscale login that owns the Mac (if it
            uses Tailscale), a session token and its own device key, all in the phone's secure storage. It also keeps a queue of
            up to 5,000 of its own connection events in a local database, uploads them to your Mac, and then deletes them. When you
            pair, it tells your Mac the phone's name, model, platform and app version so you can recognise it in Vitals. A paired browser keeps
            only a session cookie that page scripts cannot read, and nothing in browser storage.
          </Item>
          <Item>
            <Strong>Alerts:</Strong> Pressure Guard alerts reach your phone over the same encrypted Wi-Fi or Tailscale
            connection, and nothing else. While the app is open they
            arrive live; in the background the phone checks your Mac about every 15 minutes and shows a local notification. No
            push service is involved: not Expo, not Google Firebase, not Apple's push service.
          </Item>
        </List>
        <P>Turning Remote off stops the gateway and removes the tailnet entry. Revoking a device on the Mac signs it out at once.</P>
      </Section>

      <Section title="8. The phone app: permissions and other services">
        <P>
          The Vitals Remote phone app has no account, no analytics and no advertising. Everything above about Remote applies to
          it. It asks for these permissions, each only for the reason given:
        </P>
        <List>
          <Item>
            <Strong>Camera:</Strong> only to read the pairing QR code shown by Vitals on your Mac. Nothing is recorded or stored.
          </Item>
          <Item>
            <Strong>Local network:</Strong> to find your Mac on your Wi-Fi and connect to it directly.
          </Item>
          <Item>
            <Strong>Notifications:</Strong> to show Pressure Guard alerts. They are created on the phone; no push service is used.
          </Item>
        </List>
        <P>The phone app also talks to these services, and only these:</P>
        <List>
          <Item>
            <Strong>App updates (Expo):</Strong> the app checks Expo's update server for new versions and downloads them. The
            request carries the platform, the update channel, the app's runtime version, the ID of the update it is running, and a
            random identifier created when the app was installed; it is not linked to you or your Mac. Expo processes it under the{' '}
            <ExtLink href="https://expo.dev/privacy">Expo Privacy Policy</ExtLink>, and we can see only aggregate counts of
            update downloads.
          </Item>
          <Item>
            <Strong>Google Play:</Strong> on Android, the app asks Google Play at launch whether a store update is available.
          </Item>
          <Item>
            <Strong>QR scanner on Android (Google ML Kit):</Strong> the scanner reads the code on the phone; no image leaves it.
            ML Kit sends Google basic diagnostics (device model, Android version, app version, a per-installation identifier and
            performance metrics), as described in{' '}
            <ExtLink href="https://developers.google.com/ml-kit/android-data-disclosure">Google's ML Kit data disclosure</ExtLink>.
            On iOS the scanner uses Apple's on-device camera APIs and sends nothing.
          </Item>
          <Item>
            <Strong>Built-in Tailscale (off unless you turn it on):</Strong> the phone joins your own Tailscale network
            through Tailscale's coordination servers. It starts only when your Mac cannot be reached over Wi-Fi and stops a few
            minutes after it can. The phone appears in your Tailscale network under a name based on your phone's name and stays
            listed there until you remove it in Tailscale. Like every Tailscale client it uploads its connection logs to Tailscale. This is covered by the{' '}
            <ExtLink href="https://tailscale.com/privacy-policy">Tailscale Privacy Policy</ExtLink>.
          </Item>
        </List>
      </Section>

      <Section title="9. This website">
        <P>The website you are reading is a static page. It sets <Strong>no cookies</Strong>, embeds no advertising, and uses no
        fingerprinting. It uses exactly one measurement tool, disclosed here:</P>
        <List>
          <Item>
            <Strong>Vercel Web Analytics</Strong> counts page views with basic, aggregated context (page visited, referrer,
            country, browser, and device type). It is cookieless, stores no identifiers on your device, and does not follow you
            across other sites. The data is anonymized and processed by Vercel, our hosting provider, under the{' '}
            <ExtLink href="https://vercel.com/legal/privacy-policy">Vercel Privacy Policy</ExtLink>. We see only aggregate counts —
            never individual visitors.
          </Item>
          <Item>
            Your browser requests the page from our hosting provider (Vercel), which (like all web hosts) may keep standard server
            logs — IP address, user agent, requested URL, timestamp — for security and operational purposes under its own policy.
          </Item>
          <Item>
            The page queries the GitHub API from your browser to display the latest release version and download size, and the
            download buttons link to GitHub Releases. Those requests are made by your browser directly to GitHub and are covered by
            the GitHub Privacy Statement linked above.
          </Item>
        </List>
      </Section>

      <Section title="10. What we never do">
        <List>
          <Item>We do not collect, buy, sell, rent, share, or trade personal data — we have none to begin with.</Item>
          <Item>We do not profile you, advertise to you, or track you across apps or websites — the website's analytics are
          aggregate page counts, not profiles of people.</Item>
          <Item>We do not use your hardware readings for any purpose; they never reach us.</Item>
          <Item>We receive nothing from the App or the phone app automatically — a diagnostic log reaches us only if you choose
          to email it as a problem report. The one thing we can see is the aggregate count of phone app update downloads in
          Expo's dashboard (section 8), which identifies no one.</Item>
          <Item>We hold no user database, so there is nothing to breach, subpoena, or leak on our side.</Item>
        </List>
      </Section>

      <Section title="11. Data retention">
        <P>
          The App transmits nothing to us, so there is nothing of yours for us to retain. The only persistent data the App creates
          — the readings history (on by default, kept for 365 days), the diagnostic log, and your settings — lives on your Mac and
          is yours to delete. With Remote on, the gateway's activity log and command history are pruned as described in section 7. A problem
          report you choose to email is ordinary correspondence: it is kept only as long as needed to investigate the issue.
          Uninstalling the App and removing the helper deletes the App's presence from your system; your logs remain until you
          delete them, since they are your data.
          The website's aggregated, anonymous visit counts are retained in our Vercel dashboard and contain no personal
          identifiers.
        </P>
      </Section>

      <Section title="12. Your rights (GDPR, CCPA, and similar laws)">
        <P>
          Privacy laws such as the EU/UK GDPR and the California CCPA/CPRA grant rights to access, correct, delete, and port
          personal data, and to object to or restrict its processing. Because we process no personal data, there is nothing for us
          to access, correct, delete, or port — these rights are satisfied by design. If you believe we hold any personal data about
          you, contact us via the channels below and we will respond; you also retain the right to lodge a complaint with your
          local supervisory authority.
        </P>
      </Section>

      <Section title="13. Children's privacy">
        <P>
          The Services are not directed at children and collect no data from anyone, children included. We are not aware of any way
          the Services could accumulate children's personal information.
        </P>
      </Section>

      <Section title="14. Security">
        <P>
          Unless you turn on Remote, your data never leaves your Mac, so its security is governed by your machine's own protections (FileVault, macOS
          permissions, your user account). The fan-control helper is installed with root ownership and accepts state only from a
          file in a protected location. Update downloads come exclusively from GitHub Releases over HTTPS. Remote connections are
          encrypted end to end and accepted only from devices you paired.
        </P>
      </Section>

      <Section title="15. Changes to this policy">
        <P>
          If the App's behavior ever changes in a way that affects privacy — for example, if a future version began transmitting
          anything to a server automatically — this policy will be updated before that change ships, the "Last updated" date will
          change, and the change will be noted in the release notes. The current policy is always available at this address.
        </P>
      </Section>

      <Section title="16. Contact">
        <P>
          Privacy questions can be raised via <ExtLink href={DEVELOPER_URL}>rafay99.com</ExtLink> or by opening an issue on the{' '}
          <ExtLink href={REPO_URL}>GitHub repository</ExtLink>.
        </P>
      </Section>
    </LegalLayout>
  )
}
