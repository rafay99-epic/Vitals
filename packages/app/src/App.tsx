
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { DarkTheme, NavigationContainer, type Theme } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { colors } from "@vitals/ui";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { sessions } from "./connection/session.ts";
import { useSession } from "./connection/useRemote.ts";
import { ControlScreen } from "./features/control/ControlScreen.tsx";
import { GuardScreen } from "./features/guard/GuardScreen.tsx";
import { LiveScreen } from "./features/live/LiveScreen.tsx";
import { MetricScreen } from "./features/live/MetricScreen.tsx";
import { MoreScreen } from "./features/more/MoreScreen.tsx";
import { PairScreen } from "./features/pairing/PairScreen.tsx";
import { ProcessesScreen } from "./features/processes/ProcessesScreen.tsx";
import type { LiveStackParams, MetricKind, TabParams } from "./navigation/types.ts";

const theme: Theme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: colors.canvas,
    card: colors.canvas,
    border: colors.line,
    text: colors.ink,
    primary: colors.ink,
    notification: colors.bad,
  },
};

const METRIC_TITLES: Record<MetricKind, string> = {
  cpu: "CPU",
  gpu: "GPU",
  thermal: "Temperatures",
  fans: "Fans",
  memory: "Memory",
  battery: "Battery",
  power: "Power",
  network: "Network",
};

const LiveStack = createNativeStackNavigator<LiveStackParams>();
const Tabs = createBottomTabNavigator<TabParams>();

const stackOptions = {
  headerStyle: { backgroundColor: colors.canvas },
  headerTintColor: colors.ink,
  headerShadowVisible: false,
  contentStyle: { backgroundColor: colors.canvas },
} as const;

function LiveNavigator() {
  return (
    <LiveStack.Navigator screenOptions={stackOptions}>
      <LiveStack.Screen name="Live" component={LiveScreen} options={{ headerShown: false }} />
      <LiveStack.Screen name="Metric" component={MetricScreen} options={({ route }) => ({ title: METRIC_TITLES[route.params.kind] })} />
    </LiveStack.Navigator>
  );
}

function PairedTabs() {
  return (
    <Tabs.Navigator
      screenOptions={{
        headerShown: false,
        sceneStyle: { backgroundColor: colors.canvas },
        tabBarStyle: { backgroundColor: colors.canvas, borderTopColor: colors.line },
        tabBarActiveTintColor: colors.ink,
        tabBarInactiveTintColor: colors.mute,
        tabBarIconStyle: { display: "none" },
        tabBarLabelStyle: { fontSize: 13, fontWeight: "600" },
      }}
    >
      <Tabs.Screen name="LiveTab" component={LiveNavigator} options={{ title: "Live" }} />
      <Tabs.Screen name="Control" component={ControlScreen} />
      <Tabs.Screen name="Processes" component={ProcessesScreen} />
      <Tabs.Screen name="Guard" component={GuardScreen} />
      <Tabs.Screen name="More" component={MoreScreen} />
    </Tabs.Navigator>
  );
}

function Root() {
  const session = useSession();
  useEffect(() => sessions.start(), []);
  if (session.status === "loading") {
    return (
      <View className="flex-1 items-center justify-center bg-canvas">
        <ActivityIndicator color={colors.ink} />
      </View>
    );
  }
  return session.status === "paired" ? <PairedTabs /> : <PairScreen />;
}

export function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.canvas }}>
      <SafeAreaProvider>
        <NavigationContainer theme={theme}>
          <StatusBar style="light" />
          <View className="flex-1 bg-canvas">
            <Root />
          </View>
        </NavigationContainer>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
