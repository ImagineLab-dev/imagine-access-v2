/**
 * Maqueta de la entrada en el correo del ticket.
 *
 * Formato horizontal: QR a la izquierda, datos del evento en el medio, arte
 * del evento a la derecha.
 *
 * Todo se arma con <table> y atributos HTML viejos a propósito. Outlook
 * renderiza con el motor de Word: ignora flexbox, grid, y buena parte de
 * position. Una maqueta que se ve perfecta en el navegador puede quedar
 * apilada y rota ahí, que es donde abre buena parte de la gente.
 *
 * En pantallas angostas las tres columnas se apilan por media query. Gmail en
 * Android las ignora, así que los anchos están elegidos para que la fila siga
 * siendo legible aunque no se apile.
 */

export interface DatosEntrada {
    /** cid del QR ya adjunto al correo, sin el prefijo "cid:". */
    qrCid: string
    numero?: number
    total?: number
    ticketId: string
    eventoNombre: string
    fecha: string
    hora: string
    lugar?: string
    direccion?: string
    ciudad?: string
    tipo: string
    organizador?: string
    /** URL pública del arte del evento. Si falta, la columna no se dibuja. */
    imagenUrl?: string | null
}

const escapar = (v: string) =>
    v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;')

function dato(etiqueta: string, valor: string): string {
    if (!valor) return ''
    return `
      <tr>
        <td style="padding:0 0 12px 0;">
          <div style="color:#8A94A6;font-size:11px;letter-spacing:.8px;text-transform:uppercase;">${escapar(etiqueta)}</div>
          <div style="color:#111;font-size:15px;font-weight:600;line-height:1.4;margin-top:2px;">${valor}</div>
        </td>
      </tr>`
}

/**
 * Estilos de apilado para pantallas angostas.
 * Se inyecta una sola vez por correo, no por entrada.
 */
export const estilosEntrada = `
<style>
  @media only screen and (max-width: 620px) {
    .ticket-col { display:block !important; width:100% !important; max-width:100% !important; }
    .ticket-art { padding-top:16px !important; }
    .ticket-sep { display:none !important; }
  }
</style>`

export function bloqueEntrada(d: DatosEntrada): string {
    const conArte = Boolean(d.imagenUrl)
    const encabezado = (d.total ?? 1) > 1
        ? `<div style="color:#8A94A6;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;padding:0 0 12px 0;">Entrada ${d.numero} de ${d.total}</div>`
        : ''

    const lugarCompleto = [d.lugar, d.ciudad].filter(Boolean).map(escapar).join(' · ')

    return `
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;background:#fff;border:1px solid #E4E8EF;border-radius:14px;margin:0 0 18px 0;">
  <tr>
    <td style="padding:22px;">
      ${encabezado}
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
        <tr>

          <!-- QR -->
          <td class="ticket-col" valign="top" width="180" style="width:180px;">
            <img src="cid:${escapar(d.qrCid)}" alt="QR" width="160" height="160"
                 style="display:block;width:160px;height:160px;border:0;" />
            <div style="color:#111;font-size:10px;font-weight:700;letter-spacing:.6px;margin-top:10px;line-height:1.4;">
              MOSTRÁ ESTE CÓDIGO AL INGRESAR
            </div>
            <div style="color:#A8AFBC;font-size:9px;margin-top:4px;word-break:break-all;">${escapar(d.ticketId)}</div>
          </td>

          <!-- Separador punteado, como el troquel de una entrada -->
          <td class="ticket-sep" width="24" style="width:24px;">
            <div style="border-left:2px dashed #DCE1EA;height:170px;margin:0 auto;width:1px;"></div>
          </td>

          <!-- Datos -->
          <td class="ticket-col" valign="top" style="padding:0;">
            <div style="color:#111;font-size:19px;font-weight:800;line-height:1.25;padding:0 0 14px 0;">
              ${escapar(d.eventoNombre)}
            </div>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
              ${dato('Fecha', `${escapar(d.fecha)} · ${escapar(d.hora)} hs`)}
              ${dato('Lugar', lugarCompleto)}
              ${dato('Entrada', escapar(d.tipo.toUpperCase()))}
              ${d.organizador ? dato('Organiza', escapar(d.organizador)) : ''}
            </table>
            ${d.direccion ? `<a href="${escapar(d.direccion)}" style="display:inline-block;margin-top:2px;color:#2563EB;font-size:13px;text-decoration:none;font-weight:600;">Ver ubicación &rsaquo;</a>` : ''}
          </td>

          ${conArte ? `
          <!-- Arte del evento -->
          <td class="ticket-col ticket-art" valign="top" width="170" style="width:170px;padding-left:18px;">
            <img src="${escapar(d.imagenUrl!)}" alt="" width="160"
                 style="display:block;width:160px;max-width:160px;height:auto;border:0;border-radius:10px;" />
          </td>` : ''}

        </tr>
      </table>
    </td>
  </tr>
</table>`
}
