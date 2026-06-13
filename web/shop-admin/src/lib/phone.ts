// Mirror of normalizePhoneNumber() in app/dukan/lib/auth/auth_controller.dart.
// Mobile + web must agree on E.164 normalization so a cashier signing in
// from either surface lands on the same auth.users row.

import { defaultCountryCode } from "shared";

export class PhoneFormatError extends Error {
  constructor() {
    super("invalid_phone");
    this.name = "PhoneFormatError";
  }
}

const E164 = /^\+[1-9]\d{7,14}$/;

export function normalizePhoneNumber(raw: string): string {
  let phone = raw.replace(/[\s\-()]/g, "");

  if (phone.startsWith("00")) {
    phone = "+" + phone.slice(2);
  } else if (phone.startsWith("0")) {
    phone = `${defaultCountryCode}${phone.slice(1)}`;
  } else if (!phone.startsWith("+")) {
    phone = `${defaultCountryCode}${phone}`;
  }

  if (!E164.test(phone)) {
    throw new PhoneFormatError();
  }
  return phone;
}
