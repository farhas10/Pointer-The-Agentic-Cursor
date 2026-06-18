import "dotenv/config";

import { serve } from "@hono/node-server";

import { getConfig } from "./config.js";
import { getProvider } from "./llm/registry.js";
import { createApp } from "./server.js";

function main(): void {
  const config = getConfig();
  const app = createApp();
  const provider = getProvider();

  serve(
    {
      fetch: app.fetch,
      port: config.PORT,
    },
    (info) => {
      // eslint-disable-next-line no-console
      console.log(
        `pointer-backend listening on http://localhost:${info.port} (provider=${provider.name})`,
      );
    },
  );
}

main();
