import { Store } from "@vitals/client-runtime";

export const onboarded = new Store<boolean | null>(true);

export const finishOnboarding = (): void => {};
