import { FastifyInstance } from 'fastify';

const style = `<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,system-ui,sans-serif;background:#1B2D4F;color:#fff;min-height:100vh}.container{max-width:700px;margin:0 auto;padding:40px 24px}h1{color:#C5A55A;font-size:28px;margin-bottom:8px}h2{color:#C5A55A;font-size:20px;margin:24px 0 8px}p,li{color:rgba(255,255,255,0.7);line-height:1.7;margin-bottom:12px}a{color:#C5A55A}ul{padding-left:20px}.logo{text-align:center;margin-bottom:24px;font-size:32px;color:#C5A55A;font-weight:bold}.btn{display:inline-block;background:linear-gradient(135deg,#C5A55A,#D4B96A);color:#1B2D4F;padding:14px 28px;border-radius:12px;text-decoration:none;font-weight:bold}input,textarea,select{width:100%;padding:14px;border:1px solid rgba(197,165,90,0.3);border-radius:10px;background:rgba(255,255,255,0.08);color:#fff;font-size:16px;margin-bottom:12px}textarea{height:120px;resize:vertical}input:focus,textarea:focus{outline:none;border-color:#C5A55A}.footer{text-align:center;margin-top:40px;color:rgba(255,255,255,0.3);font-size:13px}</style>`;

function wrap(title: string, body: string): string {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} — wAIpoint</title>${style}</head><body><div class="container"><div class="logo">wAIpoint</div>${body}<div class="footer">Helwan Holdings © 2026</div></div></body></html>`;
}

export async function pageRoutes(app: FastifyInstance): Promise<void> {
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
}
