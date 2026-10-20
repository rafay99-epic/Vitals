import { Reveal } from '../ui/Reveal'
import { Em, SectionTitle } from '../ui/text'
import { Trace } from '../ui/Trace'

const PROMISES = [
  ['No account.', 'Pair with a code from your own Mac. Nothing to sign up for.'],
  ['No cloud.', 'Readings go from your Mac to your phone. No relay, no server of ours in between.'],
  ['No push server.', 'Alarms reach your phone by checking your Mac directly, even with the app closed.'],
  ['Revoke any time.', 'Remove a phone on the Mac and it is signed out at once.'],
] as const

function End({ name, detail }: { name: string; detail: string }) {
  return (
    <div className="grid justify-items-center gap-1.5 font-mono text-[11px] text-ink2">
      <b className="font-serif text-[32px] font-normal leading-none text-ink md:text-[40px]">{name}</b>
      {detail}
    </div>
  )
}

export function Private() {
  return (
    <Reveal className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <SectionTitle>
        Private to <Em>your tailnet.</Em>
      </SectionTitle>
      <div className="rise my-12 grid items-center gap-6 md:grid-cols-[auto_1fr_auto] md:gap-7">
        <End name="Phone" detail="iPhone · Android · Web" />
        <div className="grid gap-2">
          <Trace channel="tele" beats={90} width={800} height={44} className="h-11 w-full" />
          <span className="text-center font-mono text-[10.5px] text-dim">Tailscale between your own devices · owner identity checked on every request</span>
        </div>
        <End name="Mac" detail="Vitals gateway" />
      </div>
      <div className="grid gap-px border-y border-line bg-line sm:grid-cols-2 lg:grid-cols-4">
        {PROMISES.map(([title, body]) => (
          <div key={title} className="rise grid content-start gap-2 bg-bg py-6 sm:px-5">
            <b className="font-serif-italic text-[30px] font-normal leading-none md:text-[34px]">{title}</b>
            <p className="m-0 font-sans text-[13px] leading-[1.55] text-ink2">{body}</p>
          </div>
        ))}
      </div>
    </Reveal>
  )
}
