/**
 * Local web dev CORS proxy — forwards browser requests to mingalarbuy.com.
 *
 * Usage (from backend/):
 *   npm run proxy
 *
 * Then run Flutter web:
 *   flutter run -d chrome
 */
const express = require('express');
const http = require('http');
const https = require('https');
const { URL } = require('url');

const TARGET_ORIGIN = process.env.TARGET_ORIGIN || 'https://mingalarbuy.com';
const PORT = Number(process.env.PORT || 8787);

const targetUrl = new URL(TARGET_ORIGIN);
const upstream = targetUrl.protocol === 'https:' ? https : http;

const app = express();
app.use(express.raw({ type: '*/*', limit: '25mb' }));

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  } else {
    res.setHeader('Access-Control-Allow-Origin', '*');
  }
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader(
    'Access-Control-Allow-Methods',
    'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
  );
  const requested = req.headers['access-control-request-headers'];
  res.setHeader(
    'Access-Control-Allow-Headers',
    requested ||
      'Authorization, Content-Type, Accept, Accept-Language, User-Agent, Idempotency-Key, X-PlanetMM-Client, X-PlanetMM-Version, X-PlanetMM-Build, X-PlanetMM-Platform',
  );
  res.setHeader('Access-Control-Max-Age', '86400');

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  next();
});

app.all('*', (req, res) => {
  const path = req.originalUrl || req.url;
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.origin;
  delete headers.referer;
  delete headers.connection;
  delete headers['content-length'];

  const options = {
    protocol: targetUrl.protocol,
    hostname: targetUrl.hostname,
    port: targetUrl.port || (targetUrl.protocol === 'https:' ? 443 : 80),
    method: req.method,
    path,
    headers: {
      ...headers,
      host: targetUrl.host,
    },
  };

  const proxyReq = upstream.request(options, (proxyRes) => {
    res.status(proxyRes.statusCode || 502);
    Object.entries(proxyRes.headers).forEach(([key, value]) => {
      const lower = key.toLowerCase();
      if (
        lower === 'access-control-allow-origin' ||
        lower === 'transfer-encoding'
      ) {
        return;
      }
      if (value !== undefined) {
        res.setHeader(key, value);
      }
    });
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (error) => {
    console.error('[cors_proxy] error:', error.message);
    if (!res.headersSent) {
      res.status(502).json({
        error: 'proxy_failed',
        message: error.message,
        target: TARGET_ORIGIN,
      });
    }
  });

  if (req.method !== 'GET' && req.method !== 'HEAD' && req.body?.length) {
    proxyReq.write(req.body);
  }
  proxyReq.end();
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`CORS proxy listening on http://127.0.0.1:${PORT}`);
  console.log(`Forwarding to ${TARGET_ORIGIN}`);
});
