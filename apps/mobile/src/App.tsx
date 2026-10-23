import { type BottomTabBarProps, createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { DarkTheme, type LinkingOptions, NavigationContainer, type Theme } from "@react-navigation/native";
import { createNativeStackNavigator, type NativeStackNavigationOptions } from "@react-navigation/native-stack";
import { sessions } from "@vitals/app/connection/session.ts";
import { useRemote, useSession } from "@vitals/app/connection/useRemote.ts";
import { OnboardingScreen } from "@vitals/app/features/onboarding/OnboardingScreen.tsx";
import { FindMacScreen } from "@vitals/app/features/pairing/FindMacScreen.tsx";
import { PairScreen } from "@vitals/app/features/pairing/PairScreen.tsx";
import { WelcomeFlow } from "@vitals/app/features/pairing/WelcomeFlow.tsx";
import { checkPlay, startPlayUpdate } from "@vitals/app/features/updates/playUpdate.ts";
import { hideSplash } from "@vitals/app/lib/splash.ts";
import { isDevBuild } from "@vitals/app/lib/variant.ts";
import { finishOnboarding, onboarded } from "@vitals/app/persistence/onboarding.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { discoverySupported } from "@vitals/discovery";
import Constants from "expo-constants";
import { StatusBar } from "expo-status-bar";
import { useEffect, useState } from "react";
import { AppState, StyleSheet, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { checkForUpdate, launchedNewUpdate, updateState } from "./lib/updates.ts";
import { type HomeStackParams, navigationRef, openUpdates, type SettingsStackParams, type TabParams } from "./navigation.ts";
import { PendingStrip } from "./PendingStrip.tsx";
import { AlertsScreen } from "./screens/AlertsScreen.tsx";
import { AppsScreen } from "./screens/AppsScreen.tsx";
import { ChannelScreen } from "./screens/ChannelScreen.tsx";
import { ControlScreen } from "./screens/ControlScreen.tsx";
import { HomeScreen } from "./screens/HomeScreen.tsx";
import { ConnectionScreen, DiagnosticsRoute, HelpScreen, NotificationsScreen, PhoneScreen, SettingsScreen, UpdatesScreen } from "./screens/SettingsScreens.tsx";
import { color, Dock, type DockTab, SheetHost, toast, ToastHost } from "./ui/index.ts";

const theme: Theme = {
  ...DarkTheme,
  colors: { ...DarkTheme.colors, background: color.bg, card: color.bg, border: color.line, text: color.ink, primary: color.yellow, notification: color.red },
};

const scheme = Constants.expoConfig?.scheme;
const prefix = typeof scheme === "string" ? `${scheme}://` : null;

const linking: LinkingOptions<TabParams> = {
  enabled: prefix !== null,
  prefixes: prefix === null ? [] : [prefix],
  filter: (url) => !/:\/\/pair\b/.test(url),
  config: {
    screens: {
      HomeTab: { path: "home", screens: { Home: "", Channel: ":channel" } },
      Apps: "apps",
      Control: "control",
      Alerts: "alerts",
      SettingsTab: { path: "settings", screens: { Settings: "", Connection: "connection", Notifications: "notifications", Updates: "updates", Phone: "phone", Help: "help", ...(isDevBuild ? { Diagnostics: "diagnostics" } : {}) } },
    },
  },
};

const HomeStack = createNativeStackNavigator<HomeStackParams>();
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

function SettingsNavigator() {
  return (
    <SettingsStack.Navigator screenOptions={push}>
      <SettingsStack.Screen name="Settings" component={SettingsScreen} />
      <SettingsStack.Screen name="Connection" component={ConnectionScreen} />
      <SettingsStack.Screen name="Notifications" component={NotificationsScreen} />
      <SettingsStack.Screen name="Updates" component={UpdatesScreen} />
      <SettingsStack.Screen name="Phone" component={PhoneScreen} />
      <SettingsStack.Screen name="Help" component={HelpScreen} />
      {isDevBuild ? <SettingsStack.Screen name="Diagnostics" component={DiagnosticsRoute} /> : null}
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
  return <Dock state={state} navigation={navigation} tabs={{ ...TAB_BASE, Alerts: { ...TAB_BASE.Alerts, badge: alerted } }} />;
}

const renderDock = (props: BottomTabBarProps) => <DockBar {...props} />;

/** Tells the user, quietly, when an update is ready and after it has installed. */
function useUpdateToasts() {
  useEffect(() => {
    void launchedNewUpdate().then((updated) => {
      if (updated) toast.show("Vitals is up to date", { action: "View", onAction: openUpdates });
    });
    let previous = updateState.get()._tag;
    return updateState.subscribe(() => {
      const next = updateState.get()._tag;
      if (next === "Ready" && previous !== "Ready") toast.show("A new version is ready", { action: "View", onAction: openUpdates });
      previous = next;
    });
  }, []);
}

function Shell() {
  useRemoteToasts();
  useUpdateToasts();
  return (
    <View style={styles.fill}>
      <Tabs.Navigator
        tabBar={renderDock}
        screenOptions={{ headerShown: false, animation: "shift", sceneStyle: { backgroundColor: color.bg } }}
      >
        <Tabs.Screen name="HomeTab" component={HomeNavigator} />
        <Tabs.Screen name="Apps" component={AppsScreen} />
        <Tabs.Screen name="Control" component={ControlScreen} />
        <Tabs.Screen name="Alerts" component={AlertsScreen} />
        <Tabs.Screen name="SettingsTab" component={SettingsNavigator} />
      </Tabs.Navigator>
      <ToastHost pinned={<PendingStrip />} />
      <SheetHost />
    </View>
  );
}

function Unpaired() {
  const ready = useStore(onboarded);
  const [scan, setScan] = useState(!discoverySupported);
  if (ready === null) return <View style={styles.fill} />;
  if (!ready) return <OnboardingScreen />;
  return scan ? <PairScreen onFind={discoverySupported ? () => setScan(false) : undefined} /> : <FindMacScreen onScan={() => setScan(true)} />;
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

/** Background update checks. Nothing here ever blocks the app or swaps the screen. */
function useQuietUpdates() {
  useEffect(() => {
    void checkForUpdate();
    void checkPlay().then((play) => {
      if (play._tag === "Available") toast.show(`Vitals ${play.version} is on Google Play`, { action: "Update", onAction: () => void startPlayUpdate() });
    });
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") void checkForUpdate();
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
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: color.bg },
});
