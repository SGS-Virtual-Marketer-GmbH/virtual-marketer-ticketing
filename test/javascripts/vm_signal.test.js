// Plain Node check for App.VmSignal (app/assets/javascripts/app/lib/app_post/vm_signal.coffee).
// Not part of the Rails suite, which has no JS runner. Run with any CoffeeScript
// 1.x on the module path:
//
//   NODE_PATH=/path/to/node_modules node test/javascripts/vm_signal.test.js
//
// The file is compiled on the fly and run against a minimal App stub, so the
// decision logic is tested exactly as shipped.

const fs = require('fs')
const path = require('path')
const assert = require('assert')
const vm = require('vm')

let coffee
try { coffee = require('coffeescript') } catch (e) { coffee = require('coffee-script') }

const states = {
  1: { name: 'new' }, 2: { name: 'open' }, 3: { name: 'clarification' }, 4: { name: 'closed' }, 5: { name: 'merged' },
}
let customMap
const App = {
  Config: { get: (key) => (key === 'vm_signal_map' ? customMap : undefined) },
  TicketState: { find: (id) => states[id] },
  i18n: { translateContent: (s) => s },
}
const underscore = {
  extend: Object.assign,
  isObject: (o) => o !== null && typeof o === 'object',
}

const source = fs.readFileSync(path.join(__dirname, '../../app/assets/javascripts/app/lib/app_post/vm_signal.coffee'), 'utf8')
const sandbox = { App, _: underscore, __: (s) => s, Date, isNaN }
vm.createContext(sandbox)
vm.runInContext(coffee.compile(source, { bare: true }), sandbox)
const Sig = sandbox.App.VmSignal

const T1 = '2026-10-09T08:00:00Z'
const T2 = '2026-10-09T09:00:00Z'
const keyOf = (ticket) => { const s = Sig.of(ticket); return s && s.key }

const cases = [
  // [description, ticket, expected key]
  ['closed is no signal',                    { state_id: 4, last_contact_customer_at: T2 }, null],
  ['merged counts as closed',                { state_id: 5 }, null],
  ['no state is no signal',                  { }, null],
  ['new',                                    { state_id: 1 }, 'neu'],
  ['new beats a customer timestamp',         { state_id: 1, last_contact_customer_at: T2 }, 'neu'],
  ['customer wrote last',                    { state_id: 2, last_contact_customer_at: T2, last_contact_agent_at: T1 }, 'antwort'],
  ['customer wrote, agent never did',        { state_id: 2, last_contact_customer_at: T1 }, 'antwort'],
  ['customer reply beats clarification',     { state_id: 3, last_contact_customer_at: T2, last_contact_agent_at: T1 }, 'antwort'],
  ['clarification, agent wrote last',        { state_id: 3, last_contact_customer_at: T1, last_contact_agent_at: T2 }, 'wartet_kollege'],
  ['clarification, no contact at all',       { state_id: 3 }, 'wartet_kollege'],
  ['agent wrote last',                       { state_id: 2, last_contact_customer_at: T1, last_contact_agent_at: T2 }, 'wartet_kunde'],
  ['agent wrote, customer never did',        { state_id: 2, last_contact_agent_at: T1 }, 'wartet_kunde'],
  ['open without any contact',               { state_id: 2 }, 'arbeit'],
  ['same second counts as in progress',      { state_id: 2, last_contact_customer_at: T1, last_contact_agent_at: T1 }, 'arbeit'],
  ['unparsable timestamp is ignored',        { state_id: 2, last_contact_customer_at: 'x', last_contact_agent_at: T1 }, 'wartet_kunde'],
]
for (const [name, ticket, expected] of cases) {
  assert.strictEqual(keyOf(ticket), expected, name)
}

// ourTurn: filled badge = our move
assert.strictEqual(Sig.of({ state_id: 1 }).ourTurn, true)
assert.strictEqual(Sig.of({ state_id: 3 }).ourTurn, false)
assert.strictEqual(Sig.of({ state_id: 2, last_contact_agent_at: T1 }).ourTurn, false)

// configuration: other state names, and "wartet_kunde" switched off
customMap = { colleague: ['pending reminder'], waitingForCustomer: false }
states[6] = { name: 'pending reminder' }
assert.strictEqual(keyOf({ state_id: 6 }), 'wartet_kollege')
assert.strictEqual(keyOf({ state_id: 3 }), 'arbeit', 'clarification is plain open once remapped')
assert.strictEqual(keyOf({ state_id: 2, last_contact_customer_at: T1, last_contact_agent_at: T2 }), 'arbeit')
customMap = undefined

// queue order: neu, antwort, arbeit, wartet_kollege, wartet_kunde, closed; stable inside a group
const queue = [
  { id: 1, state_id: 4 },
  { id: 2, state_id: 2, last_contact_agent_at: T1 },
  { id: 3, state_id: 3 },
  { id: 4, state_id: 2 },
  { id: 5, state_id: 2, last_contact_customer_at: T2 },
  { id: 6, state_id: 1 },
  { id: 7, state_id: 1 },
]
assert.strictEqual(Sig.sort(queue).map((t) => t.id).join(","), "6,7,5,4,3,2,1")

// badge markup carries icon and label, never colour alone
const html = Sig.badge(Sig.of({ state_id: 1 }))
assert.ok(/vm-sig--neu/.test(html) && /vm-sig--on/.test(html) && /<svg/.test(html) && />Neu</.test(html))
assert.strictEqual(Sig.badge(null), '')

console.log("vm_signal: all checks passed")
