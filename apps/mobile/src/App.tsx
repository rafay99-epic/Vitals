import { type BottomTabBarProps, createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { DarkTheme, getFocusedRouteNameFromRoute, type LinkingOptions, NavigationContainer, type Theme } from "@react-navigation/native";
import { createNativeStackNavigator, type NativeStackNavigationOptions } from "@react-navigation/native-stack";
import { sessions } from "@vitals/app/connection/session.ts";
import { useRemote, useSession } from "@vitals/app/connection/useRemote.ts";
import { OnboardingScreen } from "@vitals/app/features/onboarding/OnboardingScreen.tsx";
import { FindMacScreen } from "@vitals/app/features/pairing/FindMacScreen.tsx";
import { PairScreen } from "@vitals/app/features/pairing/PairScreen.tsx";
import { WelcomeFlow } from "@vitals/app/features/pairing/WelcomeFlow.tsx";
import { hideSplash } from "@vitals/app/lib/splash.ts";
import { isStoreBuild } from "@vitals/app/lib/variant.ts";
import { finishOnboarding, onboarded } from "@vitals/app/persistence/onboarding.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { discoverySupported } from "@vitals/discovery";
import Constants from "expo-constants";
import { StatusBar } from "expo-status-bar";
import { useEffect, useState } from "react";
import { AppState, Linking, StyleSheet, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { ClipboardSync } from "./ClipboardSync.tsx";
import { LinkSync } from "./LinkSync.tsx";
import { ShareSync } from "./ShareSync.tsx";
import { CopyStrip } from "./CopyStrip.tsx";
import { DropStrips } from "./DropTransfers.tsx";
import { checkPlay } from "./lib/play.ts";
import { checkForUpdate } from "./lib/updates.ts";
import { type ControlStackParams, type HomeStackParams, navigationRef, type SettingsStackParams, type TabParams } from "./navigation.ts";
import { ConnectionCheck, openCheck } from "./ConnectionCheck.tsx";
import { PairOffer } from "./PairOffer.tsx";
import { PendingStrip } from "./PendingStrip.tsx";
import { ClipboardScreen } from "./screens/ClipboardScreen.tsx";
import { AlertsScreen } from "./screens/AlertsScreen.tsx";
import { AppsScreen } from "./screens/AppsScreen.tsx";
import { ChannelScreen } from "./screens/ChannelScreen.tsx";
import { ControlScreen } from "./screens/ControlScreen.tsx";
import { FilesScreen } from "./screens/FilesScreen.tsx";
import { FolderScreen } from "./screens/FolderScreen.tsx";
import { RecentScreen } from "./screens/RecentScreen.tsx";
import { TerminalScreen } from "./screens/TerminalScreen.tsx";
import { TransfersScreen } from "./screens/TransfersScreen.tsx";
import { HomeScreen } from "./screens/HomeScreen.tsx";
import { PreviewScreen } from "./screens/PreviewScreen.tsx";
import { ConnectionScreen, DiagnosticsRoute, HelpScreen, NotificationsScreen, PhoneScreen, SettingsScreen } from "./screens/SettingsScreens.tsx";
import { UpdatesScreen } from "./screens/UpdatesScreen.tsx";
import { TransferStrip } from "./Transfers.tsx";
import { UpdateSync, useUpdateStatus } from "./UpdateSync.tsx";
import { color, Dock, type DockTab, SheetHost, toast, ToastHost } from "./ui/index.ts";

const theme: Theme = {
  ...DarkTheme,
  colors: { ...DarkTheme.colors, background: color.bg, card: color.bg, border: color.line, text: color.ink, primary: color.yellow, notification: color.red },
};

const scheme = Constants.expoConfig?.scheme;
const prefix = typeof scheme === "string" ? `${scheme}://` : null;

/** Sharing into Vitals opens `<scheme>://expo-sharing`; that lands on Control, and the share inbox opens Clipboard or Files with a send sheet. */
const shareLanding = (url: string | null): string | null => (url !== null && prefix !== null && url.startsWith(`${prefix}expo-sharing`) ? `${prefix}control` : url);

const linking: LinkingOptions<TabParams> = {
  enabled: prefix !== null,
  prefixes: prefix === null ? [] : [prefix],
  filter: (url) => !/:\/\/(pair\b|clipboard\/send\b)/.test(url),
  getInitialURL: async () => shareLanding((await Linking.getInitialURL()) ?? null),
  subscribe: (listener) => {
    const subscription = Linking.addEventListener("url", ({ url }) => listener(shareLanding(url) ?? url));
    return () => subscription.remove();
  },
  config: {
    screens: {
      HomeTab: { path: "home", screens: { Home: "", Channel: ":channel" } },
      Apps: "apps",
      Control: { path: "control", screens: { Control: "", Clipboard: "clipboard", Files: "files", Transfers: "transfers" } },
      Alerts: "alerts",
      SettingsTab: { path: "settings", screens: { Settings: "", Connection: "connection", Notifications: "notifications", Updates: "updates", Phone: "phone", Help: "help", ...(isStoreBuild ? {} : { Diagnostics: "diagnostics" }) } },
    },
  },
};

const HomeStack = createNativeStackNavigator<HomeStackParams>();
const ControlStack = createNativeStackNavigator<ControlStackParams>();
const SettingsStack = createNativeStackNavigator<SettingsStackParams>();
const Tabs = createBottomTabNavigator<TabParams>();

/** Pushes slide in from the right on both platforms; Android gets predictive back for free. */
const push: NativeStackNavigationOptions = { headerShown: false, animation: "slide_from_right", contentStyle: { backgroundColor: color.bg }, gestureEnabled: true };

function HomeNavigator() {
  return (
    <HomeStack.Navigator screenOptions={push}>
      <HomeStack.Screen name="Home" component={HomeScreen} />
      <HomeStack.Screen name="Channel" component={ChannelScreen} />
    </HomeStack.Navigator>
  );
}

function ControlNavigator() {
  return (
    <ControlStack.Navigator screenOptions={push}>
      <ControlStack.Screen name="Control" component={ControlScreen} />
      <ControlStack.Screen name="Clipboard" component={ClipboardScreen} />
      <ControlStack.Screen name="Files" component={FilesScreen} />
      <ControlStack.Screen name="Folder" component={FolderScreen} />
      <ControlStack.Screen name="Recent" component={RecentScreen} />
      <ControlStack.Screen name="Preview" component={PreviewScreen} />
      <ControlStack.Screen name="Transfers" component={TransfersScreen} />
      <ControlStack.Screen name="Terminal" component={TerminalScreen} />
    </ControlStack.Navigator>
  );
}

function SettingsNavigator() {
  return (
    <SettingsStack.Navigator screenOptions={push}>
      <SettingsStack.Screen name="Settings" component={SettingsScreen} />
      <SettingsStack.Screen name="Connection" component={ConnectionScreen} />
      <SettingsStack.Screen name="Notifications" component={NotificationsScreen} />
      <SettingsStack.Screen name="Updates" component={UpdatesScreen} />
      <SettingsStack.Screen name="Phone" component={PhoneScreen} />
      <SettingsStack.Screen name="Help" component={HelpScreen} />
      {isStoreBuild ? null : <SettingsStack.Screen name="Diagnostics" component={DiagnosticsRoute} />}
    </SettingsStack.Navigator>
  );
}

const TAB_BASE: Readonly<Record<keyof TabParams, DockTab>> = {
  HomeTab: { label: "Home", icon: "home" },
  Apps: { label: "Apps", icon: "apps" },
  Control: { label: "Control", icon: "control" },
  Alerts: { label: "Alerts", icon: "bell" },
  SettingsTab: { label: "Settings", icon: "gear" },
};

/** Sends errors the shared Remote reports (failed commands) into the mobile toast. */
function useRemoteToasts() {
  const remote = useRemote();
  useEffect(
    () =>
      remote.toast.subscribe(() => {
        const next = remote.toast.get();
        if (next !== null) toast.show(next.message, { tone: next.tone });
      }),
    [remote],
  );
}

function DockBar({ state, navigation }: BottomTabBarProps) {
  const alerted = useStore(useRemote().events.alerts).length > 0;
  const update = useUpdateStatus();
  const tab = state.routes[state.index];
  const focused = tab === undefined ? undefined : getFocusedRouteNameFromRoute(tab);
  if (focused === "Terminal" || focused === "Preview") return null;
  return <Dock state={state} navigation={navigation} tabs={{ ...TAB_BASE, Alerts: { ...TAB_BASE.Alerts, badge: alerted ? color.red : undefined }, SettingsTab: { ...TAB_BASE.SettingsTab, badge: update.waiting ? color.yellow : undefined } }} />;
}

const renderDock = (props: BottomTabBarProps) => <DockBar {...props} />;

function Shell() {
  useRemoteToasts();
  return (
    <View style={styles.fill}>
      <Tabs.Navigator
        tabBar={renderDock}
        screenOptions={{ headerShown: false, animation: "shift", sceneStyle: { backgroundColor: color.bg } }}
      >
        <Tabs.Screen name="HomeTab" component={HomeNavigator} />
        <Tabs.Screen name="Apps" component={AppsScreen} />
        <Tabs.Screen name="Control" component={ControlNavigator} />
        <Tabs.Screen name="Alerts" component={AlertsScreen} />
        <Tabs.Screen name="SettingsTab" component={SettingsNavigator} />
      </Tabs.Navigator>
      <ToastHost
        pinned={
          <>
            <PendingStrip />
            <TransferStrip />
            <DropStrips />
            <CopyStrip />
          </>
        }
      />
      <SheetHost />
      <ClipboardSync />
      <ShareSync />
      <LinkSync />
      <UpdateSync />
    </View>
  );
}

function Unpaired() {
  const ready = useStore(onboarded);
  const [scan, setScan] = useState(!discoverySupported);
  if (ready === null) return <View style={styles.fill} />;
  if (!ready) return <OnboardingScreen />;
  return scan ? <PairScreen onFind={discoverySupported ? () => setScan(false) : undefined} /> : <FindMacScreen onScan={() => setScan(true)} onWhy={openCheck} />;
}

function Root() {
  const session = useSession();
  const welcome = useStore(sessions.welcome);
  useEffect(() => sessions.start(), []);
  useEffect(() => {
    if (session.status === "paired") finishOnboarding();
  }, [session.status]);
  if (session.status === "loading") return <View style={styles.fill} />;
  if (session.status === "unpaired") return <Unpaired />;
  return welcome ? <WelcomeFlow /> : <Shell />;
}

/** Background update checks on launch and on coming back. Nothing here blocks the app; UpdateSync asks. */
function useQuietUpdates() {
  useEffect(() => {
    void checkForUpdate();
    void checkPlay();
    const subscription = AppState.addEventListener("change", (state) => {
      if (state !== "active") return;
      void checkForUpdate();
      void checkPlay();
    });
    return () => subscription.remove();
  }, []);
}

export function App() {
  useQuietUpdates();
  useEffect(() => hideSplash(), []);
  return (
    <GestureHandlerRootView style={styles.fill}>
      <SafeAreaProvider>
        <StatusBar style="light" />
        <NavigationContainer ref={navigationRef} theme={theme} linking={linking}>
          <Root />
        </NavigationContainer>
        <PairOffer />
        <ConnectionCheck />
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: color.bg },
});
