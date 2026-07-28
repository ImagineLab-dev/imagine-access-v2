/**
 * Maqueta de la entrada en el correo del ticket.
 *
 * Dos columnas: a la izquierda el arte del evento arriba y el QR abajo; a la
 * derecha toda la informacion.
 *
 * Empezo con tres columnas (QR, datos, arte) y en el celular quedaba ilegible:
 * Gmail ignora las media queries, asi que no se apilaba, y la columna del
 * medio terminaba en unos 90px partiendo cada palabra en dos renglones.
 *
 * Todo se arma con <table> y atributos HTML viejos a propósito. Outlook
 * renderiza con el motor de Word: ignora flexbox, grid, y buena parte de
 * position. Una maqueta que se ve perfecta en el navegador puede quedar
 * apilada y rota ahí, que es donde abre buena parte de la gente.
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

    // Dos columnas y no tres: en el celular Gmail ignora las media queries, y
    // con tres la columna del medio quedaba de unos 90px, partiendo cada
    // palabra en dos renglones. Con dos, la de datos respira.
    //
    // Izquierda: arte arriba, QR abajo. Derecha: toda la informacion.
    return `
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;background:#fff;border:1px solid #E4E8EF;border-radius:14px;margin:0 0 18px 0;">
  <tr>
    <td style="padding:20px;">
      ${encabezado}
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
        <tr>

          <!-- Columna izquierda: arte arriba, QR abajo -->
          <td class="ticket-col" valign="top" width="170" style="width:170px;padding-right:18px;">
            ${conArte ? `
            <img src="${escapar(d.imagenUrl!)}" alt="" width="150"
                 style="display:block;width:150px;max-width:150px;height:auto;border:0;border-radius:10px;margin:0 0 14px 0;" />` : ''}
            <img src="cid:${escapar(d.qrCid)}" alt="QR" width="150" height="150"
                 style="display:block;width:150px;height:150px;border:0;" />
            <div style="color:#111;font-size:10px;font-weight:700;letter-spacing:.5px;margin-top:8px;line-height:1.4;">
              MOSTRÁ ESTE CÓDIGO AL INGRESAR
            </div>
          </td>

          <!-- Columna derecha: toda la informacion -->
          <td class="ticket-col" valign="top" style="padding:0;border-left:2px dashed #DCE1EA;padding-left:18px;">
            <div style="color:#111;font-size:20px;font-weight:800;line-height:1.25;padding:0 0 16px 0;">
              ${escapar(d.eventoNombre)}
            </div>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
              ${dato('Fecha', `${escapar(d.fecha)}`)}
              ${dato('Hora', `${escapar(d.hora)} hs`)}
              ${dato('Lugar', lugarCompleto)}
              ${dato('Entrada', escapar(d.tipo.toUpperCase()))}
              ${d.organizador ? dato('Organiza', escapar(d.organizador)) : ''}
            </table>
            ${d.direccion ? `<a href="${escapar(d.direccion)}" style="display:inline-block;margin-top:4px;color:#2563EB;font-size:13px;text-decoration:none;font-weight:600;">Ver ubicación &rsaquo;</a>` : ''}
            <div style="color:#C2C8D4;font-size:9px;margin-top:14px;word-break:break-all;">${escapar(d.ticketId)}</div>
          </td>

        </tr>
      </table>
    </td>
  </tr>
</table>`
}
