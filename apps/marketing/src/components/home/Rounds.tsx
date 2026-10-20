import { Reveal } from '../ui/Reveal'
import { DemoNote, Em, Lede, SectionTitle } from '../ui/text'
import { ChartPhone, OrdersPhone, WardPhone } from './Phones'

const STEPS = ['Open Vitals, then Remote, on the Mac.', 'Scan the code with your phone.', 'Hold Rest. The display goes first, then the Mac sleeps.'] as const

export function Rounds() {
  return (
    <Reveal id="remote" className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <div className="grid items-center gap-12 xl:grid-cols-[360px_1fr] xl:gap-10">
        <div className="rise grid content-start gap-5">
          <SectionTitle>
            Rounds <Em>from bed.</Em>
          </SectionTitle>
          <Lede>The same chart on iPhone, Android and the web. Read it, quiet it, put it to sleep, calm the agents. It travels over your own tailnet, straight to your Mac.</Lede>
          <ol className="m-0 list-none border-t border-line p-0">
            {STEPS.map((step, index) => (
              <li key={step} className="grid grid-cols-[34px_1fr] border-b border-line py-3 font-sans text-[14px] leading-[1.5]">
                <span className="font-mono text-[11px] leading-[1.9] text-pulse">{String(index + 1).padStart(2, '0')}</span>
                {step}
              </li>
            ))}
          </ol>
        </div>
        <div className="rise flex justify-center gap-[22px] xl:justify-end">
          <div className="hidden lg:block">
            <ChartPhone />
          </div>
          <div className="lg:mt-[70px]">
            <OrdersPhone />
          </div>
          <div className="hidden lg:block">
            <WardPhone />
          </div>
        </div>
        <DemoNote className="text-center xl:col-start-2" />
      </div>
    </Reveal>
  )
}
