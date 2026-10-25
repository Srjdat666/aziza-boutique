export const WHATSAPP_PHONE = '218944467520';
export const STORE_PHONES = ['0919652924', '0944467520'] as const;
export const STORE_ADDRESS = 'سرت، شارع 5، العمارة رقم 89';
export const SITE_NAME = 'AZIZA Boutique';
export const TAGLINE = 'حيث تعبّر الأناقة عنكِ';
export const GOATCOUNTER = 'https://azizaboutique.goatcounter.com/count';

export const SOCIAL = {
  instagram: 'https://www.instagram.com/aziza.boutique01',
  tiktok: 'https://www.tiktok.com/@aziza.store1',
  snapchat: 'https://snapchat.com/t/UYMV2sWB',
  facebook: 'https://www.facebook.com/share/1M7TuNEcYZ/',
} as const;

export const ORDER_STATUS_LABELS: Record<string, string> = {
  new: 'جديد',
  confirmed: 'مؤكد',
  preparing: 'قيد التجهيز',
  out_for_delivery: 'خرج للتوصيل',
  delivered: 'سُلّم',
  cancelled: 'ملغى',
};

export const BADGE_LABELS: Record<string, string> = {
  new: 'وصل حديثاً',
  last_piece: 'آخر قطعة',
  sold_out: 'نفدت',
  sale: 'خصم',
};
