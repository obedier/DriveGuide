import { FastifyInstance } from 'fastify';

const style = `<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,system-ui,sans-serif;background:#1B2D4F;color:#fff;min-height:100vh}.container{max-width:700px;margin:0 auto;padding:40px 24px}h1{color:#C5A55A;font-size:28px;margin-bottom:8px}h2{color:#C5A55A;font-size:20px;margin:24px 0 8px}p,li{color:rgba(255,255,255,0.7);line-height:1.7;margin-bottom:12px}a{color:#C5A55A}ul{padding-left:20px}.logo{text-align:center;margin-bottom:24px;font-size:32px;color:#C5A55A;font-weight:bold}.btn{display:inline-block;background:linear-gradient(135deg,#C5A55A,#D4B96A);color:#1B2D4F;padding:14px 28px;border-radius:12px;text-decoration:none;font-weight:bold}input,textarea,select{width:100%;padding:14px;border:1px solid rgba(197,165,90,0.3);border-radius:10px;background:rgba(255,255,255,0.08);color:#fff;font-size:16px;margin-bottom:12px}textarea{height:120px;resize:vertical}input:focus,textarea:focus{outline:none;border-color:#C5A55A}.footer{text-align:center;margin-top:40px;color:rgba(255,255,255,0.3);font-size:13px}</style>`;

function wrap(title: string, body: string): string {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} — wAIpoint</title>${style}</head><body><div class="container"><div class="logo">wAIpoint</div>${body}<div class="footer">Helwan Holdings © 2026</div></div></body></html>`;
}

export async function pageRoutes(app: FastifyInstance): Promise<void> {
  // Apple App Site Association — enables Universal Links so
  // https://waipoint.o11r.com/tour/<id> and /passenger/<id> deep-link
  // into the iOS app. Must be served at this exact path with
  // Content-Type: application/json and no redirect.
  app.get('/.well-known/apple-app-site-association', async (_req, reply) => {
    reply.type('application/json');
    return {
      applinks: {
        apps: [],
        details: [
          {
            appID: 'U3972W2GDJ.com.privatetourai.app',
            paths: ['/tour/*', '/passenger/*']
          }
        ]
      }
    };
  });

  app.get('/privacy', async (_req, reply) => {
    reply.type('text/html');
    return wrap('Privacy Policy', `
<h1>Privacy Policy</h1>
<p>Last updated: April 2026</p>
<h2>Information We Collect</h2>
<ul>
<li><strong>Location data</strong> — GPS for audio narration triggers. Only during active tours.</li>
<li><strong>Account info</strong> — Email, name, photo from Apple/Google/email sign-in.</li>
<li><strong>Tour preferences</strong> — Themes, transport modes, custom prompts.</li>
<li><strong>Usage data</strong> — Tour history, ratings, playback progress.</li>
</ul>
<h2>How We Use It</h2>
<ul>
<li>Generate personalized tours via AI (Google Gemini)</li>
<li>Trigger audio narration by GPS position</li>
<li>Save tours and process subscriptions</li>
</ul>
<h2>Data Sharing</h2>
<p>We never sell your data. Shared only with: Google (Maps/AI/TTS), Firebase (auth), Apple (payments), VectorCharts (nautical charts).</p>
<h2>Your Rights</h2>
<p>Delete your account anytime from Profile. Email <a href="mailto:support@waipoint.app">support@waipoint.app</a> for data requests.</p>
<h2>Children</h2>
<p>Not directed at children under 13.</p>
`);
  });

  app.get('/terms', async (_req, reply) => {
    reply.type('text/html');
    return wrap('Terms of Service', `
<h1>Terms of Service</h1>
<p>Last updated: April 2026</p>
<h2>1. Service</h2>
<p>wAIpoint generates AI-powered narrated tours. Content may contain inaccuracies — always follow traffic laws.</p>
<h2>2. Subscriptions</h2>
<p>Weekly $7.99, Monthly $14.99, Annual $79.99. Auto-renews unless canceled 24 hours before period ends. Manage in Apple ID settings.</p>
<h2>3. AI Content</h2>
<p>Tours are AI-generated and may not be perfectly accurate. We are not liable for navigation decisions based on tour content.</p>
<h2>4. User Content</h2>
<p>Tours you share become available to the community. You retain ownership of custom prompts.</p>
<h2>Contact</h2>
<p><a href="mailto:support@waipoint.app">support@waipoint.app</a></p>
`);
  });

  app.get('/support', async (_req, reply) => {
    reply.type('text/html');
    return wrap('Customer Support', `
<h1>Customer Support</h1>
<p>We're here to help!</p>
<h2>Contact Us</h2>
<form action="mailto:support@waipoint.app" method="get" enctype="text/plain">
<input type="email" name="from" placeholder="Your email address" required>
<input type="text" name="subject" placeholder="Subject" required>
<textarea name="body" placeholder="Describe your issue..."></textarea>
<button type="submit" class="btn" style="width:100%;border:none;cursor:pointer;font-size:16px">Send Message</button>
</form>
<h2>FAQ</h2>
<p><strong>Cancel subscription?</strong> Settings > Apple ID > Subscriptions > wAIpoint > Cancel</p>
<p><strong>Tour won't generate?</strong> Check internet connection. Try shorter duration or more specific location.</p>
<p><strong>Boat tours?</strong> Select Boat transport mode for waterway-accessible stops with nautical charts.</p>
<p><strong>Offline?</strong> Audio caches automatically after first playback.</p>
`);
  });

  app.get('/feedback', async (_req, reply) => {
    reply.type('text/html');
    return wrap('Feedback', `
<h1>Share Your Feedback</h1>
<p>Help us make wAIpoint better! We read every message.</p>
<form action="mailto:feedback@waipoint.app" method="get" enctype="text/plain">
<input type="email" name="from" placeholder="Your email (optional)">
<select name="subject"><option>Feature Request</option><option>Bug Report</option><option>Tour Quality</option><option>General</option></select>
<textarea name="body" placeholder="Tell us what you think..."></textarea>
<button type="submit" class="btn" style="width:100%;border:none;cursor:pointer;font-size:16px">Send Feedback</button>
</form>
`);
  });

  // Marketing landing page
  app.get('/', async (_req, reply) => {
    reply.type('text/html');
    return `<!DOCTYPE html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>wAIpoint — Your Private AI Tour Guide</title>
<meta name="description" content="AI-powered guided tours with GPS-triggered audio narration. Explore any city like a local — by car, foot, bike, or boat.">
<meta property="og:title" content="wAIpoint — Private AI Tour Guide">
<meta property="og:description" content="Instant personalized tours with GPS-triggered audio. 5 transport modes. Works anywhere.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://waipoint.o11r.com">
<meta name="apple-itunes-app" content="app-id=6761740179">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,system-ui,sans-serif;background:#1B2D4F;color:#fff}
.hero{text-align:center;padding:80px 24px 60px;background:linear-gradient(180deg,#1B2D4F 0%,#0D1A2F 100%)}
.hero h1{font-size:48px;color:#C5A55A;margin-bottom:16px;letter-spacing:-1px}
.hero h1 span{color:#fff}
.hero p{font-size:20px;color:rgba(255,255,255,0.6);max-width:600px;margin:0 auto 32px;line-height:1.5}
.cta{display:inline-block;background:linear-gradient(135deg,#C5A55A,#D4B96A);color:#1B2D4F;padding:18px 40px;border-radius:14px;text-decoration:none;font-weight:bold;font-size:18px;margin:8px}
.cta-outline{background:transparent;border:2px solid #C5A55A;color:#C5A55A}
.features{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:32px;max-width:1100px;margin:0 auto;padding:60px 24px}
.feature{text-align:center;padding:32px 24px;background:rgba(45,90,61,0.15);border-radius:20px;border:1px solid rgba(197,165,90,0.1)}
.feature .icon{font-size:48px;margin-bottom:16px}
.feature h3{color:#C5A55A;font-size:20px;margin-bottom:8px}
.feature p{color:rgba(255,255,255,0.6);line-height:1.6}
.modes{text-align:center;padding:60px 24px;background:rgba(0,0,0,0.15)}
.modes h2{color:#C5A55A;font-size:32px;margin-bottom:32px}
.mode-grid{display:flex;justify-content:center;gap:24px;flex-wrap:wrap}
.mode{width:120px;padding:24px 16px;background:rgba(255,255,255,0.05);border-radius:16px;text-align:center}
.mode .emoji{font-size:36px;margin-bottom:8px}
.mode .label{color:#C5A55A;font-weight:bold;font-size:14px}
.pricing{text-align:center;padding:60px 24px}
.pricing h2{color:#C5A55A;font-size:32px;margin-bottom:32px}
.price-cards{display:flex;justify-content:center;gap:20px;flex-wrap:wrap}
.price-card{width:200px;padding:32px 20px;background:rgba(255,255,255,0.05);border-radius:20px;border:1px solid rgba(197,165,90,0.1)}
.price-card.featured{border:2px solid #C5A55A;position:relative}
.price-card.featured::before{content:'BEST VALUE';position:absolute;top:-12px;left:50%;transform:translateX(-50%);background:#C5A55A;color:#1B2D4F;padding:4px 16px;border-radius:20px;font-size:11px;font-weight:bold}
.price-card .period{color:#C5A55A;font-weight:bold;font-size:18px}
.price-card .price{font-size:32px;font-weight:bold;margin:8px 0}
.price-card .per{color:rgba(255,255,255,0.4);font-size:14px}
.footer{text-align:center;padding:40px;color:rgba(255,255,255,0.3);font-size:13px}
.footer a{color:#C5A55A;text-decoration:none;margin:0 12px}
</style></head><body>
<div class="hero">
<h1>w<span>AI</span>point</h1>
<p>Your private AI tour guide. Instant personalized tours with GPS-triggered audio narration — by car, foot, bike, or boat.</p>
<a href="https://apps.apple.com/app/waipoint/id6761740179" class="cta">Download on App Store</a>
<a href="#features" class="cta cta-outline">Learn More</a>
</div>

<div class="features" id="features">
<div class="feature"><div class="icon">🧭</div><h3>AI-Generated Tours</h3><p>Enter any destination and duration. Our AI researches the area, selects the best stops, and builds a compelling narrative arc — mixing iconic highlights with hidden gems.</p></div>
<div class="feature"><div class="icon">🎧</div><h3>GPS Audio Narration</h3><p>Professional narration triggers automatically as you move. Approach commentary, at-stop details, and between-stop color about neighborhoods you're passing through.</p></div>
<div class="feature"><div class="icon">⛵</div><h3>Premium Boat Tours</h3><p>Verified waterway stops with nautical chart navigation. Cruise Millionaire's Row, dock at waterfront restaurants, and explore hidden channels with a captain's narration.</p></div>
<div class="feature"><div class="icon">✨</div><h3>Personalized For You</h3><p>Custom themes like "homes of movie stars" or "best street food." Set your transport mode, speed, and even vessel specs for boat tours. Every tour is unique.</p></div>
<div class="feature"><div class="icon">📱</div><h3>Premium Design</h3><p>Map-first interface with 3D views, stop photos, animated compass loading, and a navy-and-gold aesthetic that feels as premium as the experience.</p></div>
<div class="feature"><div class="icon">🌎</div><h3>Works Anywhere</h3><p>Starting with premium South Florida coverage — Miami, Fort Lauderdale, Palm Beach — with hundreds of US cities available. New cities added regularly.</p></div>
</div>

<div class="modes">
<h2>Five Ways to Explore</h2>
<div class="mode-grid">
<div class="mode"><div class="emoji">🚗</div><div class="label">Drive</div></div>
<div class="mode"><div class="emoji">🚶</div><div class="label">Walk</div></div>
<div class="mode"><div class="emoji">🚲</div><div class="label">Bike</div></div>
<div class="mode"><div class="emoji">⛵</div><div class="label">Boat</div></div>
<div class="mode"><div class="emoji">✈️</div><div class="label">Fly</div></div>
</div>
</div>

<div class="pricing">
<h2>Simple Pricing</h2>
<div class="price-cards">
<div class="price-card"><div class="period">Free</div><div class="price">$0</div><div class="per">Preview any tour</div></div>
<div class="price-card"><div class="period">Weekly</div><div class="price">$7.99</div><div class="per">/week</div></div>
<div class="price-card"><div class="period">Monthly</div><div class="price">$14.99</div><div class="per">/month</div></div>
<div class="price-card featured"><div class="period">Annual</div><div class="price">$79.99</div><div class="per">$6.67/month</div></div>
</div>
<br><br>
<a href="https://apps.apple.com/app/waipoint/id6761740179" class="cta">Start Exploring Free</a>
</div>

<div class="footer">
<p>Helwan Holdings &copy; 2026</p>
<p><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/support">Support</a><a href="/feedback">Feedback</a></p>
</div>
</body></html>`;
  });
}
