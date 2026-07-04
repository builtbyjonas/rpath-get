import express from "express";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const app = express();
const cacheHeader =
  "public, max-age=300, s-maxage=300, stale-while-revalidate=86400";
const installSh = readFileSync(
  join(process.cwd(), "scripts", "install.sh"),
  "utf8",
);
const installPs1 = readFileSync(
  join(process.cwd(), "scripts", "install.ps1"),
  "utf8",
);
const uninstallSh = readFileSync(
  join(process.cwd(), "scripts", "uninstall.sh"),
  "utf8",
);
const uninstallPs1 = readFileSync(
  join(process.cwd(), "scripts", "uninstall.ps1"),
  "utf8",
);

const scriptRoutes = {
  "/install.sh": {
    body: installSh,
    type: "text/x-shellscript; charset=utf-8",
  },
  "/install.ps1": {
    body: installPs1,
    type: "text/plain; charset=utf-8",
  },
  "/uninstall.sh": {
    body: uninstallSh,
    type: "text/x-shellscript; charset=utf-8",
  },
  "/uninstall.ps1": {
    body: uninstallPs1,
    type: "text/plain; charset=utf-8",
  },
};

for (const [route, script] of Object.entries(scriptRoutes)) {
  app.get(route, (_request, response) => {
    response
      .status(200)
      .set("Cache-Control", cacheHeader)
      .type(script.type)
      .send(script.body);
  });
}

app.get("/healthz", (_request, response) => {
  response
    .status(200)
    .set("Cache-Control", "no-store")
    .type("application/json")
    .send({ ok: true });
});

app.use((_request, response) => {
  response.status(404).type("text/plain; charset=utf-8").send("not found\n");
});

app.use((error, _request, response, _next) => {
  console.error(error);
  response
    .status(500)
    .set("Cache-Control", "no-store")
    .type("text/plain; charset=utf-8")
    .send("internal server error\n");
});

if (!process.env.VERCEL && process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000);
  app.listen(port, () => {
    console.log(`get.rpath.dev listening on http://localhost:${port}`);
  });
}

export default app;
