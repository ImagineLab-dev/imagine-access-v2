/**
 * Roles del sistema y los predicados que deciden qué puede hacer cada uno.
 *
 * Existe porque no existía. El rol `superadmin` se agregó después que el resto
 * del sistema de permisos, y cada Edge Function comparaba el rol con la cadena
 * `'admin'` por su cuenta: `userRole !== 'admin'`, `role === 'admin'`,
 * `['admin','rrpp'].includes(role)`. Trece comparaciones repartidas en once
 * archivos, ninguna de las cuales contemplaba al super-admin.
 *
 * El efecto real fue que el dueño de la plataforma, al recibir su rol, quedó
 * SIN poder crear eventos, emitir invitaciones, ver su equipo, gestionar
 * dispositivos de puerta, anular tickets, reenviar correos ni descargar
 * reportes. Y el panel le mostraba ceros en vez de un error, porque
 * `get_staff_dashboard` no encontraba ninguna rama que le correspondiera.
 *
 * La lección no es "faltaba un caso" sino que la regla vivía copiada en trece
 * lugares. Con la regla acá, agregar un rol mañana es editar este archivo.
 *
 * En la base de datos el equivalente es `public.is_admin()`, que ya incluye a
 * ambos. Las dos definiciones tienen que decir lo mismo.
 */

export const ROL_ADMIN = 'admin'
export const ROL_SUPERADMIN = 'superadmin'
export const ROL_RRPP = 'rrpp'
export const ROL_PUERTA = 'door'

/**
 * Administra una organización: el admin de esa organización, o el super-admin
 * de la plataforma, que está por encima de todas.
 *
 * Es el reemplazo de `rol !== 'admin'`. Un super-admin nunca puede tener MENOS
 * permisos que un admin común — eso no es una decisión de producto, es la
 * definición de la palabra.
 */
export function esAdmin(rol: string | null | undefined): boolean {
    return rol === ROL_ADMIN || rol === ROL_SUPERADMIN
}

/**
 * Puede emitir y anular tickets: quien administra, más el RRPP, que es su
 * trabajo.
 *
 * Reemplaza a `['admin','rrpp'].includes(rol)` y a
 * `rol !== 'admin' && rol !== 'rrpp'`.
 */
export function puedeGestionarTickets(rol: string | null | undefined): boolean {
    return esAdmin(rol) || rol === ROL_RRPP
}

/** Solo el super-admin de la plataforma. Para lo que cruza organizaciones. */
export function esSuperAdmin(rol: string | null | undefined): boolean {
    return rol === ROL_SUPERADMIN
}
