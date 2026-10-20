import { type BottomTabBarProps, createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { DarkTheme, type LinkingOptions, NavigationContainer, type Theme } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { colors, type GlyphName, Mono, TabBar, Toast, useWide } from "@vitals/ui";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { Platform, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider, useSafeAreaInsets } from "react-native-safe-area-context";

import { sessions } from "./connection/session.ts";
import { useRemote, useSession } from "./connection/useRemote.ts";
import { AlarmsScreen } from "./features/alarms/AlarmsScreen.tsx";
import { ChannelScreen } from "./features/chart/ChannelScreen.tsx";
import { ChartScreen } from "./features/chart/ChartScreen.tsx";
import { DiagnosticsScreen } from "./features/diagnostics/DiagnosticsScreen.tsx";
import { OnboardingScreen } from "./features/onboarding/OnboardingScreen.tsx";
import { OrdersScreen } from "./features/orders/OrdersScreen.tsx";
import { PairScreen } from "./features/pairing/PairScreen.tsx";
import { WelcomeFlow } from "./features/pairing/WelcomeFlow.tsx";
import { RecordScreen } from "./features/record/RecordScreen.tsx";
import { PlayUpdateSheet } from "./features/updates/PlayUpdateSheet";
import { UpdateGate } from "./features/updates/UpdateGate";
import { UpdatesScreen } from "./features/updates/UpdatesScreen";
import { WardScreen } from "./features/ward/WardScreen.tsx";
import { useAppFonts } from "./lib/fonts";
import { hostOf } from "./lib/host.ts";
import type { ChartStackParams, RecordStackParams, TabParams } from "./navigation/types.ts";
import { finishOnboarding, onboarded } from "./persistence/onboarding";
import { useStore } from "./state/useStore.ts";

const theme: Theme = {
  ...DarkTheme,
  colors: { ...DarkTheme.colors, background: colors.bg, card: colors.bg, border: colors.line, text: colors.ink, primary: colors.ink, notification: colors.alarmHigh },
};

const linking: LinkingOptions<TabParams> = {
  enabled: Platform.OS === "web",
  prefixes: [],
  config: {
    screens: {
      ChartTab: { path: "chart", screens: { Chart: "", Channel: ":channel" } },
      Orders: "orders",
      Ward: "ward",
      Alarms: "alarms",
      RecordTab: { path: "record", screens: { Record: "", Updates: "updates", Diagnostics: "diagnostics" } },
    },
  },
};

const TABS: Record<keyof TabParams, { readonly label: string; readonly glyph: GlyphName }> = {
  ChartTab: { label: "Chart", glyph: "chart" },
  Orders: { label: "Orders", glyph: "orders" },
  Ward: { label: "Ward", glyph: "ward" },
  Alarms: { label: "Alarms", glyph: "alarms" },
  RecordTab: { label: "Record", glyph: "record" },
};

const isTab = (name: string): name is keyof TabParams => name in TABS;

const ChartStack = createNativeStackNavigator<ChartStackParams>();
const RecordStack = createNativeStackNavigator<RecordStackParams>();
const Tabs = createBottomTabNavigator<TabParams>();

const stackOptions = { headerShown: false, contentStyle: { backgroundColor: colors.bg } } as const;

function ChartNavigator() {
  return (
    <ChartStack.Navigator screenOptions={stackOptions}>
      <ChartStack.Screen name="Chart" component={ChartScreen} />
      <ChartStack.Screen name="Channel" component={ChannelScreen} />
    </ChartStack.Navigator>
  );
}

function RecordNavigator() {
  return (
    <RecordStack.Navigator screenOptions={stackOptions}>
      <RecordStack.Screen name="Record" component={RecordScreen} />
      <RecordStack.Screen name="Updates" component={UpdatesScreen} />
      <RecordStack.Screen name="Diagnostics" component={DiagnosticsScreen} />
    </RecordStack.Navigator>
  );
}

function BedsideTabBar({ state, navigation, wide }: BottomTabBarProps & { readonly wide: boolean }) {
  const remote = useRemote();
  const alarmed = useStore(remote.events.alerts).length > 0;
  const items = state.routes.flatMap((route) => (isTab(route.name) ? [{ key: route.name, ...TABS[route.name], badge: route.name === "Alarms" && alarmed }] : []));
  const active = state.routes[state.index]?.name ?? "ChartTab";
  const select = (name: string) => {
    const route = state.routes.find((candidate) => candidate.name === name);
    if (route === undefined) return;
    const event = navigation.emit({ type: "tabPress", target: route.key, canPreventDefault: true });
    if (name === active || event.defaultPrevented) return;
    navigation.navigate(route.name, route.params);
  };
  return <TabBar items={items} active={active} onSelect={select} rail={wide} footer={<Mono>{hostOf(remote.credentials.baseUrl)}</Mono>} />;
}

const phoneTabBar = (props: BottomTabBarProps) => <BedsideTabBar {...props} wide={false} />;
const wideTabBar = (props: BottomTabBarProps) => <BedsideTabBar {...props} wide />;

const TAB_BAR_TOP = 58;
const TOAST_GAP = 12;

function ToastHost({ wide }: { readonly wide: boolean }) {
  const toast = useStore(useRemote().toast);
  const insets = useSafeAreaInsets();
  const bottom = wide ? TOAST_GAP : TAB_BAR_TOP + Math.max(insets.bottom, 10) + TOAST_GAP;
  return toast === null ? null : <Toast key={toast.at} message={toast.message} tone={toast.tone} bottom={bottom} />;
}

function PairedTabs() {
  const wide = useWide();
  return (
    <View className="flex-1">
      <Tabs.Navigator
        tabBar={wide ? wideTabBar : phoneTabBar}
        screenOptions={{ headerShown: false, tabBarPosition: wide ? "left" : "bottom", sceneStyle: { backgroundColor: colors.bg } }}
      >
        <Tabs.Screen name="ChartTab" component={ChartNavigator} options={{ title: "Chart" }} />
        <Tabs.Screen name="Orders" component={OrdersScreen} />
        <Tabs.Screen name="Ward" component={WardScreen} />
        <Tabs.Screen name="Alarms" component={AlarmsScreen} />
        <Tabs.Screen name="RecordTab" component={RecordNavigator} options={{ title: "Record" }} />
      </Tabs.Navigator>
      <ToastHost wide={wide} />
    </View>
  );
}

function Unpaired() {
  const ready = useStore(onboarded);
  if (ready === null) return <View className="flex-1 bg-bg" />;
  return ready ? <PairScreen /> : <OnboardingScreen />;
}

function Root() {
  const session = useSession();
  const welcome = useStore(sessions.welcome);
  useEffect(() => sessions.start(), []);
  useEffect(() => {
    if (session.status === "paired") finishOnboarding();
  }, [session.status]);
  if (session.status === "loading") return <View className="flex-1 bg-bg" />;
  if (session.status === "unpaired") return <Unpaired />;
  return welcome ? <WelcomeFlow /> : <PairedTabs />;
}

export function App() {
  const fontsReady = useAppFonts();
  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.bg }}>
      <SafeAreaProvider>
        <StatusBar style="light" />
        {fontsReady ? (
          <UpdateGate>
            <NavigationContainer theme={theme} linking={linking}>
              <Root />
              <PlayUpdateSheet />
            </NavigationContainer>
          </UpdateGate>
        ) : (
          <View className="flex-1 bg-bg" />
        )}
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
