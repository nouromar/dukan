import { Suspense } from "react";
import { getTranslations } from "next-intl/server";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EmailForm } from "./email-form";
import { PhoneForm } from "./phone-form";
import { LoginErrorToast } from "./login-error-toast";

export default async function LoginPage() {
  const t = await getTranslations("login");
  return (
    <>
    <Suspense>
      <LoginErrorToast />
    </Suspense>
    <Card>
      <CardHeader>
        <CardTitle>{t("title")}</CardTitle>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="email" className="w-full">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="email">{t("tabEmail")}</TabsTrigger>
            <TabsTrigger value="phone">{t("tabPhone")}</TabsTrigger>
          </TabsList>
          <TabsContent value="email" className="mt-4">
            <Suspense>
              <EmailForm />
            </Suspense>
          </TabsContent>
          <TabsContent value="phone" className="mt-4">
            <Suspense>
              <PhoneForm />
            </Suspense>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
    </>
  );
}
