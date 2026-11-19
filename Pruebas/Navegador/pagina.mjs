// Prueba del JS del Navegador de Alma en un navegador de verdad (Chromium de Playwright), con páginas de ejemplo locales:
// nunca abre un sitio real (toda petición de red se corta). Saca el JS tal cual de Alma/Navegador.swift (jsPrivada) y de
// Alma/ManosAlma.swift (script) y revisa la pausa de privacidad, la lectura barata y que la página no vea marcas de Alma.
//   node Pruebas/Navegador/pagina.mjs [carpeta para capturas]
// Necesita Playwright (npm i -g playwright && npx playwright install chromium). No la corre el robot: es la prueba de quien
// cambia ese JS (el robot sí corre Pruebas/Navegador/main.swift, la lógica pura).
import { readFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw; try { pw = require('playwright'); } catch { pw = require('/opt/node22/lib/node_modules/playwright'); }
const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const crudo = (archivo, nombre) => {
  const s = readFileSync(path.join(raiz, 'Alma', archivo), 'utf8');
  const i = s.indexOf(nombre + ' = #"""'); if (i < 0) throw new Error('No encuentro ' + nombre);
  const a = s.indexOf('\n', i) + 1, b = s.indexOf('\n"""#', a);
  return s.slice(a, b);
};
const PRIVADA = crudo('Navegador.swift', 'static let jsPrivada'), MANOS = crudo('ManosAlma.swift', 'static let script');
const capturas = process.argv[2];
if (capturas) mkdirSync(capturas, { recursive: true });

let fallos = 0;
const revisa = (ok, que) => { console.log((ok ? '✓ ' : '✗ ') + que); if (!ok) fallos++; };

const navegador = await pw.chromium.launch();
const ctx = await navegador.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true });
await ctx.route('**/*', r => r.request().url().startsWith('data:') ? r.continue() : r.fulfill({ status: 200, contentType: 'text/html', body: '<html><body></body></html>' }));
await ctx.addInitScript(() => { window.__avisos = []; window.webkit = { messageHandlers: { almaPrivada: { postMessage: o => window.__avisos.push(o) } } }; });

const estilo = '<meta name="viewport" content="width=device-width"><style>body{font:16px -apple-system,system-ui,sans-serif;margin:0;padding:24px;color:#3E3F3F}input,button{font:inherit;display:block;margin:10px 0;padding:10px;width:100%;box-sizing:border-box;border:1px solid #ccc;border-radius:10px}button{background:#3E3F3F;color:#fff;border:0}</style>';
async function abrir(cuerpo) {
  const p = await ctx.newPage();
  await p.setContent('<!doctype html><html><head><title>Ejemplo</title>' + estilo + '</head><body>' + cuerpo + '</body></html>');
  await p.evaluate(PRIVADA + '\n;window.__almaPrivadaVigilar();');
  return p;
}
const manos = (p, cmd, a = {}) => p.evaluate(([codigo, cmd, a]) => JSON.parse((0, eval)(codigo + '\n;window.__almaManos(' + JSON.stringify(cmd) + ', ' + JSON.stringify(a) + ');')), [PRIVADA + '\n' + MANOS, cmd, a]);
const motivo = p => p.evaluate(() => window.__almaPrivada().motivo);

// 1. Un formulario normal: Alma ve, y la página no ve marcas de Alma en su HTML.
{
  const p = await abrir('<h1>Tu reserva</h1><p>Reserva HM4K2Q del 3 al 5 de diciembre.</p><p>Política de mascotas: no se permiten.</p><label>Nombre <input name="nombre"></label><label>Correo <input type="email" name="correo"></label>' + '<a href="#">Ver más</a>'.repeat(40) + '<button>Buscar</button>');
  revisa(await motivo(p) === '', 'formulario normal: sin pausa');
  const r = await manos(p, 'leer');
  revisa(Array.isArray(r.elementos) && r.elementos.some(l => /campo · Nombre/.test(l)), 'leer_pagina da la lista numerada');
  revisa(await p.evaluate(() => document.querySelectorAll('[data-alma-id]').length) === 0, 'la página no ve marcas de Alma (data-alma-id)');
  revisa(r.elementos.filter(l => /Ver más/.test(l)).length === 3, '«Ver más» ×40 se lee solo 3 veces (más barato)');
  const f = await manos(p, 'leer', { para: 'mascotas' });
  revisa(/mascotas/.test(f.texto) && !/HM4K2Q/.test(f.texto), 'con «para» solo vienen las líneas que importan');
  const id = r.elementos.find(l => /Nombre/.test(l)).split(' · ')[0];
  const e = await manos(p, 'escribir', { id, texto: 'Juan' });
  revisa(e.ok === true && await p.evaluate(() => document.querySelector('[name=nombre]').value) === 'Juan', 'escribir por número sigue funcionando');
  const s = await manos(p, 'senalar', { id: r.elementos.find(l => /Correo/.test(l)).split(' · ')[0], texto: 'Escribe tu correo aquí' });
  revisa(s.ok === true, 'senalar marca el campo (modo guiado)');
  if (capturas) await p.screenshot({ path: path.join(capturas, 'guiado-senalar.png') });
  await p.close();
}

// 2. Contraseña: pausa, nada se lee ni se escribe; con «Listo» se lee, pero nunca el valor.
{
  const p = await abrir('<h1>Entrar</h1><label>Correo <input name="usuario"></label><label>Contraseña <input type="password" name="pw"></label><button>Entrar</button>');
  revisa(await motivo(p) === 'clave', 'una contraseña a la vista pausa');
  revisa((await manos(p, 'leer')).te_toca === true, 'leer_pagina responde te_toca (Alma no ve)');
  revisa((await manos(p, 'escribir', { id: '1', texto: 'x' })).te_toca === true, 'escribir responde te_toca');
  revisa((await manos(p, 'senalar', { id: '1', texto: 'x' })).te_toca === true, 'senalar responde te_toca');
  const av = await p.evaluate(() => window.__avisos[window.__avisos.length - 1]);
  revisa(av && av.clave === true && !('value' in av) && Object.keys(av).every(k => typeof av[k] === 'boolean'), 'el aviso a la app solo lleva sí/no, nunca un valor');
  await p.fill('[name=pw]', 'secreta-123');
  await p.evaluate(() => document.activeElement.blur());
  const l = await manos(p, 'leer', { libre: true });
  revisa(!l.te_toca && !JSON.stringify(l).includes('secreta-123') && l.elementos.some(x => /contraseña · .*\(la escribe Juan\)/.test(x)), 'con «Listo» se lee la página, sin la contraseña');
  await p.focus('[name=pw]');
  revisa((await manos(p, 'leer', { libre: true })).te_toca === true, 'si Juan vuelve al campo, otra vez te_toca');
  await p.close();
}

// 3. Códigos, tarjetas y lo escondido.
{
  let p = await abrir('<label>Código <input autocomplete="one-time-code" name="c"></label>');
  revisa(await motivo(p) === 'codigo', 'autocomplete one-time-code pausa'); await p.close();
  p = await abrir('<p>Escribe el código que te mandamos</p>' + '<input maxlength="1" style="width:40px;display:inline-block">'.repeat(6));
  revisa(await motivo(p) === 'codigo', 'el código en 6 cajitas pausa'); await p.close();
  p = await abrir('<label>Código de verificación <input name="verif"></label>');
  revisa(await motivo(p) === 'codigo', '«Código de verificación» pausa'); await p.close();
  p = await abrir('<label>Número de tarjeta <input autocomplete="cc-number" name="t"></label>');
  revisa(await motivo(p) === 'tarjeta', 'un campo de tarjeta pausa'); await p.close();
  p = await abrir('<iframe src="https://js.stripe.com/v3/elements" width="300" height="60"></iframe>');
  revisa(await motivo(p) === 'tarjeta', 'el recuadro de pago de Stripe pausa'); await p.close();
  p = await abrir('<label>Código postal <input name="postal"></label><label>Código de cupón <input name="cupon"></label>');
  revisa(await motivo(p) === '', '«Código postal» y «cupón» no pausan'); await p.close();
  p = await abrir('<div style="display:none"><input type="password"></div><p>Hola</p>');
  revisa(await motivo(p) === '', 'una contraseña escondida no pausa'); await p.close();
  p = await abrir('<div style="height:3000px"></div><input type="password" id="abajo">');
  revisa(await motivo(p) === '', 'una contraseña fuera de la pantalla no pausa…');
  await p.focus('#abajo');
  revisa(await motivo(p) === 'clave', '…pero sí cuando tiene el cursor'); await p.close();
}

// 4. «Soy humano»: siempre Juan.
{
  let p = await abrir('<iframe title="reCAPTCHA" src="https://www.google.com/recaptcha/api2/anchor?k=x&size=normal" width="304" height="78"></iframe>');
  revisa(await motivo(p) === 'captcha', 'reCAPTCHA a la vista pausa');
  revisa((await manos(p, 'leer', { libre: true })).te_toca === true, '«Listo» no salta un captcha'); await p.close();
  p = await abrir('<div class="grecaptcha-badge"><iframe title="reCAPTCHA" src="https://www.google.com/recaptcha/api2/anchor?k=x&size=invisible" width="256" height="60"></iframe></div><input type="email">');
  revisa(await motivo(p) === '', 'el sello de reCAPTCHA invisible no pausa'); await p.close();
  p = await abrir('<h1>Verify you are human</h1><p>Press and hold the button</p>');
  revisa(await motivo(p) === 'captcha', '«Verify you are human» pausa'); await p.close();
  p = await abrir('<div class="cf-turnstile" style="width:300px;height:65px"></div>');
  revisa(await motivo(p) === 'captcha', 'Cloudflare Turnstile pausa'); await p.close();
}

// 5. El aviso llega solo cuando la página cambia (aparece el campo de contraseña después).
{
  const p = await abrir('<button id="b">Entrar</button>');
  await p.evaluate(() => { const i = document.createElement('input'); i.type = 'password'; document.body.appendChild(i); });
  await p.waitForTimeout(500);
  const av = await p.evaluate(() => window.__avisos.map(a => a.clave));
  revisa(av[0] === false && av[av.length - 1] === true, 'al aparecer una contraseña, la app se entera sola (en ~¼ s)');
  await p.close();
}

await navegador.close();
console.log(fallos ? 'FALLARON ' + fallos : 'OK: el JS del Navegador de Alma');
process.exit(fallos ? 1 : 0);
