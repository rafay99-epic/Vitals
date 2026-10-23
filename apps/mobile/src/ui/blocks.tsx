import { useNavigation } from "@react-navigation/native";
import type { ReactNode } from "react";
import { RefreshControl, ScrollView, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { Icon, type IconName } from "./Icon.tsx";
import { T } from "./Text.tsx";
import { Tap } from "./Tap.tsx";
import { color, DOCK_BOTTOM, DOCK_HEIGHT, space } from "./tokens.ts";

/** Scrolling page that clears the status bar on top and the floating dock at the bottom. */
export function Page({ children, refreshing, onRefresh }: { readonly children: ReactNode; readonly refreshing?: boolean; readonly onRefresh?: () => void }) {
  const insets = useSafeAreaInsets();
  return (
    <ScrollView
      style={styles.page}
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
      refreshControl={onRefresh === undefined ? undefined : <RefreshControl refreshing={refreshing === true} onRefresh={onRefresh} tintColor={color.dim} colors={[color.bg]} progressBackgroundColor={color.yellow} />}
    >
      <View style={{ height: insets.top + 6 }} />
      {children}
      <View style={{ height: insets.bottom + DOCK_BOTTOM + DOCK_HEIGHT + 40 }} />
    </ScrollView>
  );
}

/** Bottom padding for lists that manage their own scrolling. */
export const useDockSpace = (): number => useSafeAreaInsets().bottom + DOCK_BOTTOM + DOCK_HEIGHT + 40;

/** Big serif page title, e.g. "Apps." */
export function Title({ children, right }: { readonly children: string; readonly right?: ReactNode }) {
  return (
    <View style={styles.titleRow}>
      <T v="title" accessibilityRole="header">
        {children}
      </T>
      {right}
    </View>
  );
}

/** Back link for pushed screens. */
export function BackBar({ parent }: { readonly parent: string }) {
  const navigation = useNavigation();
  return (
    <Tap onPress={() => navigation.goBack()} accessibilityRole="button" accessibilityLabel={`Back to ${parent}`} hitSlop={12} style={styles.back}>
      <Icon name="back" size={16} color={color.yellow} weight={2.4} />
      <T v="medium" color={color.yellow}>
        {parent}
      </T>
    </Tap>
  );
}

/** Small grey heading above a group of controls. */
export function Label({ children, right }: { readonly children: string; readonly right?: string | undefined }) {
  return (
    <View style={styles.label}>
      <T v="label">{children}</T>
      {right === undefined ? null : <T v="label">{right}</T>}
    </View>
  );
}

/** Grey helper text under a group. */
export function Note({ children }: { readonly children: ReactNode }) {
  return (
    <T v="small" style={styles.note}>
      {children}
    </T>
  );
}

/** Rounded container for rows. */
export function Group({ children }: { readonly children: ReactNode }) {
  return <View style={styles.group}>{children}</View>;
}

export interface RowProps {
  readonly label: string;
  readonly detail?: string | undefined;
  readonly value?: ReactNode;
  readonly valueColor?: string;
  readonly control?: ReactNode;
  readonly onPress?: (() => void) | undefined;
  readonly danger?: boolean;
  readonly first?: boolean;
}

/** One row inside a Group. Pressable rows get a chevron. */
export function Row({ label, detail, value, valueColor = color.dim, control, onPress, danger = false, first = false }: RowProps) {
  const body = (
    <>
      <View style={styles.rowText}>
        <T v="medium" color={danger ? color.red : color.ink}>
          {label}
        </T>
        {detail === undefined ? null : <T v="small">{detail}</T>}
      </View>
      {typeof value === "string" ? (
        <T v="body" color={valueColor} numberOfLines={1} style={styles.rowValue}>
          {value}
        </T>
      ) : (
        value
      )}
      {control}
      {onPress === undefined ? null : <Icon name="chevron" size={15} color={color.mute} />}
    </>
  );
  const style = [styles.row, first ? null : styles.rowLine];
  if (onPress === undefined) return <View style={style}>{body}</View>;
  return (
    <Tap onPress={onPress} accessibilityRole="button" scale={0.99} style={style}>
      {body}
    </Tap>
  );
}

/** Full-width primary button. */
export function BigButton({ label, onPress, ghost = false, disabled = false }: { readonly label: string; readonly onPress: () => void; readonly ghost?: boolean; readonly disabled?: boolean }) {
  return (
    <Tap onPress={onPress} disabled={disabled} accessibilityRole="button" style={[styles.big, ghost ? styles.ghost : null]}>
      <T v="strong" color={ghost ? color.ink : color.bg}>
        {label}
      </T>
    </Tap>
  );
}

/** Square-ish action tile used for power and send-to-Mac actions. */
export function Tile({ icon, label, onPress, danger = false, disabled = false, raised = false }: { readonly icon: IconName; readonly label: string; readonly onPress: () => void; readonly danger?: boolean; readonly disabled?: boolean; readonly raised?: boolean }) {
  const tint = danger ? color.red : color.ink;
  return (
    <Tap onPress={onPress} disabled={disabled} accessibilityRole="button" accessibilityLabel={label} layout={styles.tileSlot} style={[styles.tile, raised ? styles.raised : null]}>
      <Icon name={icon} size={20} color={tint} />
      <T v="strong" color={tint} numberOfLines={2} style={styles.tileText}>
        {label}
      </T>
    </Tap>
  );
}

/** Three tiles per row. */
export function TileGrid({ children }: { readonly children: ReactNode }) {
  return <View style={styles.tiles}>{children}</View>;
}

/** Full-width action with an icon and a short explanation. Used in sheets. */
export function ActionRow({ icon, label, detail, onPress, disabled = false }: { readonly icon: IconName; readonly label: string; readonly detail?: string | undefined; readonly onPress: () => void; readonly disabled?: boolean }) {
  return (
    <Tap onPress={onPress} disabled={disabled} accessibilityRole="button" style={styles.action}>
      <Icon name={icon} size={20} />
      <View style={styles.rowText}>
        <T v="strong">{label}</T>
        {detail === undefined ? null : <T v="small">{detail}</T>}
      </View>
    </Tap>
  );
}

/** Bordered card for alerts. */
export function Card({ children, tone = "warn" }: { readonly children: ReactNode; readonly tone?: "warn" | "bad" | "quiet" }) {
  const border = tone === "warn" ? color.orange : tone === "bad" ? color.red : color.line2;
  return <View style={[styles.card, { borderColor: border }]}>{children}</View>;
}

/** Row of small labelled numbers. */
export function Stats({ items }: { readonly items: ReadonlyArray<{ readonly label: string; readonly value: string; readonly color?: string }> }) {
  return (
    <View style={styles.stats}>
      {items.map((item) => (
        <View key={item.label} style={styles.stat}>
          <T v="tag">{item.label.toUpperCase()}</T>
          <T v="monoStrong" color={item.color ?? color.ink}>
            {item.value}
          </T>
        </View>
      ))}
    </View>
  );
}

/** Centered quiet message for empty or loading lists. Honest words only. */
export function Empty({ title, detail }: { readonly title: string; readonly detail?: string | undefined }) {
  return (
    <View style={styles.empty}>
      <T v="medium" color={color.ink2}>
        {title}
      </T>
      {detail === undefined ? null : (
        <T v="small" style={styles.emptyDetail}>
          {detail}
        </T>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: color.bg },
  titleRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: space.gutter, paddingTop: 8, paddingBottom: 14 },
  back: { flexDirection: "row", alignItems: "center", gap: 4, alignSelf: "flex-start", paddingHorizontal: space.edge, paddingVertical: 8 },
  label: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: space.gutter, paddingTop: 6, paddingBottom: 8 },
  note: { paddingHorizontal: space.gutter, paddingBottom: 12 },
  group: { marginHorizontal: space.edge, marginBottom: 12, backgroundColor: color.s2, borderRadius: 16, overflow: "hidden" },
  row: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 14, paddingVertical: 13, minHeight: 50 },
  rowLine: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: color.line2 },
  rowText: { flex: 1, gap: 2 },
  rowValue: { maxWidth: "55%" },
  big: { marginHorizontal: space.edge, marginBottom: 8, alignItems: "center", backgroundColor: color.yellow, borderRadius: 14, paddingVertical: 14 },
  ghost: { backgroundColor: "transparent", borderWidth: 1, borderColor: color.line2 },
  tiles: { flexDirection: "row", flexWrap: "wrap", gap: 9, paddingHorizontal: space.edge, paddingBottom: 14 },
  tileSlot: { width: "30%", flexGrow: 1 },
  tile: { height: 72, borderRadius: 16, backgroundColor: color.s2, justifyContent: "center", gap: 6, paddingHorizontal: 13 },
  raised: { backgroundColor: color.s3 },
  tileText: { fontSize: 13 },
  action: { flexDirection: "row", alignItems: "center", gap: 13, marginHorizontal: space.edge, marginBottom: 7, backgroundColor: color.s3, borderRadius: 14, paddingHorizontal: 14, paddingVertical: 13 },
  card: { marginHorizontal: space.edge, marginBottom: 12, borderRadius: 18, backgroundColor: color.s2, padding: 16, borderWidth: 1 },
  stats: { flexDirection: "row", marginHorizontal: space.edge, marginBottom: 12, backgroundColor: color.s2, borderRadius: 16, paddingVertical: 12 },
  stat: { flex: 1, paddingHorizontal: 14, gap: 3 },
  empty: { alignItems: "center", paddingVertical: 32, paddingHorizontal: 24 },
  emptyDetail: { textAlign: "center", marginTop: 4 },
});
