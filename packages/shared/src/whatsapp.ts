import { WHATSAPP_PHONE } from './constants';

export type ProductWhatsAppPayload = {
  title: string;
  size: string;
  color: string;
  priceLyd: number;
  pageUrl: string;
};

export function buildProductWhatsAppUrl(payload: ProductWhatsAppPayload): string {
  const lines = [
    'مرحباً AZIZA Boutique',
    'أريد طلب:',
    payload.title,
    `المقاس: ${payload.size || '—'}`,
    `اللون: ${payload.color || '—'}`,
    `السعر: ${payload.priceLyd} د.ل`,
    payload.pageUrl,
  ];
  return `https://wa.me/${WHATSAPP_PHONE}?text=${encodeURIComponent(lines.join('\n'))}`;
}

export type OrderWhatsAppPayload = {
  orderNumber: string;
  customerName: string;
  phone: string;
  city: string;
  address: string;
  deliveryMethod: string;
  paymentMethod: string;
  totalLyd: number;
  lines: { title: string; size: string; color: string; qty: number; price: number }[];
  trackUrl: string;
};

export function buildOrderWhatsAppUrl(p: OrderWhatsAppPayload): string {
  const items = p.lines
    .map(
      (l) =>
        `• ${l.title} (${l.size}/${l.color}) ×${l.qty} = ${l.price * l.qty} د.ل`,
    )
    .join('\n');
  const text = [
    'طلب جديد من الموقع',
    `رقم الطلب: ${p.orderNumber}`,
    `الاسم: ${p.customerName}`,
    `الهاتف: ${p.phone}`,
    `المدينة: ${p.city}`,
    `العنوان: ${p.address}`,
    `التوصيل: ${p.deliveryMethod}`,
    `الدفع: ${p.paymentMethod}`,
    '',
    items,
    '',
    `الإجمالي: ${p.totalLyd} د.ل`,
    `تتبع: ${p.trackUrl}`,
  ].join('\n');
  return `https://wa.me/${WHATSAPP_PHONE}?text=${encodeURIComponent(text)}`;
}

export function buildStatusUpdateWhatsAppUrl(
  phone: string,
  orderNumber: string,
  statusLabel: string,
): string {
  const normalized = phone.replace(/\D/g, '');
  const libyaPhone = normalized.startsWith('218')
    ? normalized
    : `218${normalized.replace(/^0/, '')}`;
  const text = `مرحباً ${orderNumber}\nتحديث طلبك: ${statusLabel}\n— AZIZA Boutique`;
  return `https://wa.me/${libyaPhone}?text=${encodeURIComponent(text)}`;
}
