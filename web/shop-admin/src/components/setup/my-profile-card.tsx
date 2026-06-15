// "My profile" card — top of /setup. Lets the signed-in user set
// their display name, which then appears in the staff list, audit
// log, and anywhere else the portal shows who-did-what.

"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updateMyProfileAction } from "@/app/(dashboard)/setup/actions";

export function MyProfileCard({
  initialName,
}: {
  initialName: string;
}) {
  const t = useTranslations("setup.profile");
  const router = useRouter();
  const [name, setName] = useState(initialName);
  const [pending, startTransition] = useTransition();

  function handleSave() {
    startTransition(async () => {
      const result = await updateMyProfileAction({ displayName: name });
      if (result.ok) {
        toast.success(t("saved"));
        router.refresh();
        return;
      }
      const key = result.code === "empty" ? "errorEmpty" : "errorGeneric";
      toast.error(t(key as "errorGeneric"));
    });
  }

  const dirty = name.trim() !== initialName.trim();

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">{t("title")}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-sm text-muted-foreground">{t("description")}</p>
        <div className="space-y-2">
          <Label htmlFor="display-name">{t("nameLabel")}</Label>
          <div className="flex gap-2">
            <Input
              id="display-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("namePlaceholder")}
              maxLength={120}
            />
            <Button
              onClick={handleSave}
              disabled={pending || !dirty || name.trim().length === 0}
            >
              {pending ? t("saving") : t("save")}
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
