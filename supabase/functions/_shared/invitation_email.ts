/**
 * Correo de invitación al equipo.
 *
 * Antes no existía: `create_user` creaba la cuenta y devolvía la contraseña
 * temporal en la respuesta, así que el admin tenía que copiarla y pasarla por
 * WhatsApp. Eso deja credenciales dando vueltas en chats y depende de que
 * alguien se acuerde de explicar cómo entrar.
 *
 * Incluye las instrucciones para agregar la app a la pantalla de inicio porque
 * es donde más se traba la gente, y porque en iOS instalar no es opcional: una
 * PWA agregada al inicio queda exenta del borrado de datos a los 7 días de
 * inactividad que Safari aplica a los sitios normales. Sin instalar, la cola de
 * validaciones offline del personal de puerta puede desaparecer sola.
 */

export type Idioma = 'es' | 'en' | 'pt'

export interface DatosInvitacion {
    email: string
    tempPassword: string
    organizacion: string
    rol: string
    invitadoPor?: string
    appUrl: string
    idioma?: Idioma
}

const MARCA = {
    fondo: '#0B0F16',
    superficie: '#131A26',
    acento: '#4A9EFF',
    texto: '#FFFFFF',
    textoTenue: 'rgba(255,255,255,.62)',
    borde: 'rgba(255,255,255,.10)',
}

const ROLES: Record<Idioma, Record<string, string>> = {
    es: { admin: 'Administrador', rrpp: 'RRPP', door: 'Control de acceso' },
    en: { admin: 'Administrator', rrpp: 'Promoter', door: 'Door control' },
    pt: { admin: 'Administrador', rrpp: 'Promotor', door: 'Controle de acesso' },
}

const T: Record<Idioma, Record<string, string>> = {
    es: {
        asunto: 'Te sumaron a {org} en Imagine Access',
        hola: 'Hola',
        intro: '{quien} te sumó al equipo de <strong>{org}</strong> en Imagine Access, el sistema de control de acceso a eventos.',
        tuRol: 'Tu rol',
        credenciales: 'Tus datos de acceso',
        correo: 'Correo',
        clave: 'Contraseña temporal',
        avisoClave: 'Cambiala apenas entres, desde Perfil → Seguridad. Esta contraseña es de un solo uso práctico: cualquiera que vea este correo puede entrar con ella.',
        entrar: 'Entrar a Imagine Access',
        instalarTitulo: 'Instalá la app en tu teléfono',
        instalarPor: 'Instalada funciona sin conexión y arranca más rápido. En la puerta, con señal mala, es la diferencia entre poder escanear y no poder.',
        iphone: 'iPhone (Safari, Chrome, cualquiera)',
        iphonePasos: '1. Abrí el enlace de arriba.<br>2. Tocá el botón <strong>Compartir</strong> del navegador (el cuadrado con la flecha hacia arriba).<br>3. Elegí <strong>«Añadir a pantalla de inicio»</strong>.',
        android: 'Android',
        androidPasos: '1. Abrí el enlace de arriba.<br>2. Tocá <strong>Instalar</strong> cuando aparezca el aviso.<br>3. Si no aparece, abrí el menú ⋮ y elegí <strong>«Instalar aplicación»</strong>.',
        ayuda: 'Si no esperabas este correo, ignoralo: sin la contraseña no se puede hacer nada con tu dirección.',
        pie: 'Imagine Access · Control de acceso a eventos',
    },
    en: {
        asunto: 'You were added to {org} on Imagine Access',
        hola: 'Hi',
        intro: '{quien} added you to the <strong>{org}</strong> team on Imagine Access, the event access control system.',
        tuRol: 'Your role',
        credenciales: 'Your sign-in details',
        correo: 'Email',
        clave: 'Temporary password',
        avisoClave: 'Change it as soon as you sign in, under Profile → Security. Treat it as single-use: anyone who sees this email can sign in with it.',
        entrar: 'Sign in to Imagine Access',
        instalarTitulo: 'Install the app on your phone',
        instalarPor: 'Once installed it works offline and starts faster. At the door with poor signal, that is the difference between scanning and not scanning.',
        iphone: 'iPhone (Safari, Chrome, any browser)',
        iphonePasos: '1. Open the link above.<br>2. Tap your browser\'s <strong>Share</strong> button (the square with an up arrow).<br>3. Choose <strong>"Add to Home Screen"</strong>.',
        android: 'Android',
        androidPasos: '1. Open the link above.<br>2. Tap <strong>Install</strong> when prompted.<br>3. If nothing appears, open the ⋮ menu and choose <strong>"Install app"</strong>.',
        ayuda: 'If you were not expecting this email, ignore it: without the password nothing can be done with your address.',
        pie: 'Imagine Access · Event access control',
    },
    pt: {
        asunto: 'Voce foi adicionado a {org} no Imagine Access',
        hola: 'Ola',
        intro: '{quien} adicionou voce a equipe de <strong>{org}</strong> no Imagine Access, o sistema de controle de acesso a eventos.',
        tuRol: 'Sua funcao',
        credenciales: 'Seus dados de acesso',
        correo: 'E-mail',
        clave: 'Senha temporaria',
        avisoClave: 'Altere assim que entrar, em Perfil → Seguranca. Trate como uso unico: qualquer pessoa que veja este e-mail pode entrar com ela.',
        entrar: 'Entrar no Imagine Access',
        instalarTitulo: 'Instale o app no seu telefone',
        instalarPor: 'Instalado funciona sem conexao e abre mais rapido. Na porta, com sinal ruim, e a diferenca entre conseguir escanear ou nao.',
        iphone: 'iPhone (Safari, Chrome, qualquer um)',
        iphonePasos: '1. Abra o link acima.<br>2. Toque no botao <strong>Compartilhar</strong> do navegador (o quadrado com a seta para cima).<br>3. Escolha <strong>"Adicionar a Tela de Inicio"</strong>.',
        android: 'Android',
        androidPasos: '1. Abra o link acima.<br>2. Toque em <strong>Instalar</strong> quando aparecer o aviso.<br>3. Se nao aparecer, abra o menu ⋮ e escolha <strong>"Instalar aplicativo"</strong>.',
        ayuda: 'Se voce nao esperava este e-mail, ignore: sem a senha nada pode ser feito com seu endereco.',
        pie: 'Imagine Access · Controle de acesso a eventos',
    },
}

const escapar = (valor: string) =>
    valor.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;')

function bloqueDato(etiqueta: string, valor: string, monospace = false): string {
    return `
    <tr>
      <td style="padding:10px 0;border-bottom:1px solid ${MARCA.borde};">
        <div style="color:${MARCA.textoTenue};font-size:12px;text-transform:uppercase;letter-spacing:.6px;">${etiqueta}</div>
        <div style="color:${MARCA.texto};font-size:16px;margin-top:4px;${monospace ? 'font-family:ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:1px;' : ''}">${valor}</div>
      </td>
    </tr>`
}

function bloqueInstalacion(titulo: string, pasos: string): string {
    return `
    <div style="margin-top:14px;padding:14px 16px;background:rgba(255,255,255,.04);border-radius:10px;">
      <div style="color:${MARCA.acento};font-size:13px;font-weight:600;margin-bottom:8px;">${titulo}</div>
      <div style="color:${MARCA.textoTenue};font-size:14px;line-height:1.7;">${pasos}</div>
    </div>`
}

export function asuntoInvitacion(datos: DatosInvitacion): string {
    const t = T[datos.idioma ?? 'es']
    return t.asunto.replace('{org}', datos.organizacion)
}

export function cuerpoInvitacion(datos: DatosInvitacion): string {
    const idioma = datos.idioma ?? 'es'
    const t = T[idioma]
    const nombreRol = ROLES[idioma][datos.rol] ?? datos.rol
    const quien = datos.invitadoPor ? escapar(datos.invitadoPor) : (idioma === 'en' ? 'An administrator' : idioma === 'pt' ? 'Um administrador' : 'Un administrador')

    const intro = t.intro
        .replace('{quien}', quien)
        .replace('{org}', escapar(datos.organizacion))

    return `
<div style="background:${MARCA.fondo};padding:32px 16px;font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;">
  <div style="max-width:560px;margin:0 auto;background:${MARCA.superficie};border:1px solid ${MARCA.borde};border-radius:18px;overflow:hidden;">

    <div style="padding:28px 28px 8px;">
      <div style="color:${MARCA.acento};font-size:13px;font-weight:700;letter-spacing:2px;text-transform:uppercase;">Imagine Access</div>
      <h1 style="color:${MARCA.texto};font-size:22px;line-height:1.35;margin:14px 0 0;">${t.hola}</h1>
      <p style="color:${MARCA.textoTenue};font-size:15px;line-height:1.65;margin:12px 0 0;">${intro}</p>
    </div>

    <div style="padding:20px 28px 0;">
      <div style="color:${MARCA.textoTenue};font-size:12px;text-transform:uppercase;letter-spacing:.6px;">${t.tuRol}</div>
      <div style="display:inline-block;margin-top:6px;padding:6px 14px;border-radius:999px;background:rgba(74,158,255,.14);color:${MARCA.acento};font-size:14px;font-weight:600;">${escapar(nombreRol)}</div>
    </div>

    <div style="padding:24px 28px 0;">
      <div style="color:${MARCA.texto};font-size:15px;font-weight:600;margin-bottom:6px;">${t.credenciales}</div>
      <table style="width:100%;border-collapse:collapse;">
        ${bloqueDato(t.correo, escapar(datos.email))}
        ${bloqueDato(t.clave, escapar(datos.tempPassword), true)}
      </table>
      <p style="color:#FFC46B;font-size:13px;line-height:1.6;margin:14px 0 0;">${t.avisoClave}</p>
    </div>

    <div style="padding:26px 28px 0;text-align:center;">
      <a href="${escapar(datos.appUrl)}" style="display:inline-block;padding:14px 30px;background:${MARCA.acento};color:${MARCA.fondo};text-decoration:none;border-radius:12px;font-size:15px;font-weight:700;">${t.entrar}</a>
    </div>

    <div style="padding:30px 28px 8px;">
      <div style="color:${MARCA.texto};font-size:15px;font-weight:600;">${t.instalarTitulo}</div>
      <p style="color:${MARCA.textoTenue};font-size:14px;line-height:1.65;margin:8px 0 0;">${t.instalarPor}</p>
      ${bloqueInstalacion(t.iphone, t.iphonePasos)}
      ${bloqueInstalacion(t.android, t.androidPasos)}
    </div>

    <div style="padding:24px 28px 28px;">
      <p style="color:rgba(255,255,255,.38);font-size:12px;line-height:1.6;margin:0;">${t.ayuda}</p>
    </div>

    <div style="padding:16px 28px;background:rgba(0,0,0,.25);text-align:center;">
      <span style="color:rgba(255,255,255,.35);font-size:12px;">${t.pie}</span>
    </div>

  </div>
</div>`
}
