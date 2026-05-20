// Zombie Fighter - top-down survival shooter
// Plain HTML5 Canvas, no libraries. Just open index.html in a browser to play.

const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
}
window.addEventListener("resize", resize);
resize();

// ---- Input ----------------------------------------------------------------
const keys = {};
const mouse = { x: canvas.width / 2, y: canvas.height / 2, down: false };

window.addEventListener("keydown", (e) => {
  keys[e.key.toLowerCase()] = true;
  if (gameOver && e.key.toLowerCase() === "r") reset();
});
window.addEventListener("keyup", (e) => {
  keys[e.key.toLowerCase()] = false;
});
window.addEventListener("mousemove", (e) => {
  mouse.x = e.clientX;
  mouse.y = e.clientY;
});
window.addEventListener("mousedown", () => {
  if (gameOver) {
    reset();
    return;
  }
  mouse.down = true;
});
window.addEventListener("mouseup", () => {
  mouse.down = false;
});

// ---- Game state ------------------------------------------------------------
let player, bullets, zombies, particles;
let score, wave, spawnTimer, spawnInterval, shootCooldown, gameOver;

function reset() {
  player = {
    x: canvas.width / 2,
    y: canvas.height / 2,
    radius: 16,
    speed: 3.4,
    hp: 100,
    maxHp: 100,
  };
  bullets = [];
  zombies = [];
  particles = [];
  score = 0;
  wave = 1;
  spawnTimer = 0;
  spawnInterval = 90; // frames between zombie spawns
  shootCooldown = 0;
  gameOver = false;
}
reset();

// ---- Spawning --------------------------------------------------------------
function spawnZombie() {
  // Pick a random screen edge to come in from.
  const edge = Math.floor(Math.random() * 4);
  let x, y;
  if (edge === 0) {
    x = Math.random() * canvas.width;
    y = -30;
  } else if (edge === 1) {
    x = Math.random() * canvas.width;
    y = canvas.height + 30;
  } else if (edge === 2) {
    x = -30;
    y = Math.random() * canvas.height;
  } else {
    x = canvas.width + 30;
    y = Math.random() * canvas.height;
  }
  zombies.push({
    x,
    y,
    radius: 14,
    speed: 0.8 + Math.random() * 0.6 + wave * 0.05,
    hp: 2,
  });
}

function spawnParticles(x, y, color) {
  for (let i = 0; i < 8; i++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = Math.random() * 3 + 1;
    particles.push({
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      radius: Math.random() * 3 + 1,
      life: 25,
      color,
    });
  }
}

// ---- Update ----------------------------------------------------------------
function update() {
  if (gameOver) return;

  // Player movement
  let dx = 0;
  let dy = 0;
  if (keys["w"] || keys["arrowup"]) dy -= 1;
  if (keys["s"] || keys["arrowdown"]) dy += 1;
  if (keys["a"] || keys["arrowleft"]) dx -= 1;
  if (keys["d"] || keys["arrowright"]) dx += 1;
  if (dx !== 0 || dy !== 0) {
    const len = Math.hypot(dx, dy);
    player.x += (dx / len) * player.speed;
    player.y += (dy / len) * player.speed;
  }
  player.x = Math.max(player.radius, Math.min(canvas.width - player.radius, player.x));
  player.y = Math.max(player.radius, Math.min(canvas.height - player.radius, player.y));

  // Shooting
  if (shootCooldown > 0) shootCooldown--;
  if (mouse.down && shootCooldown <= 0) {
    const angle = Math.atan2(mouse.y - player.y, mouse.x - player.x);
    bullets.push({
      x: player.x,
      y: player.y,
      vx: Math.cos(angle) * 9,
      vy: Math.sin(angle) * 9,
      radius: 4,
      life: 80,
    });
    shootCooldown = 12;
  }

  // Bullets
  for (let i = bullets.length - 1; i >= 0; i--) {
    const b = bullets[i];
    b.x += b.vx;
    b.y += b.vy;
    b.life--;
    if (b.life <= 0 || b.x < 0 || b.x > canvas.width || b.y < 0 || b.y > canvas.height) {
      bullets.splice(i, 1);
    }
  }

  // Spawn zombies on a timer
  spawnTimer++;
  if (spawnTimer >= spawnInterval) {
    spawnTimer = 0;
    spawnZombie();
  }

  // Zombies
  for (let i = zombies.length - 1; i >= 0; i--) {
    const z = zombies[i];
    const angle = Math.atan2(player.y - z.y, player.x - z.x);
    z.x += Math.cos(angle) * z.speed;
    z.y += Math.sin(angle) * z.speed;

    // Bullet hits zombie
    for (let j = bullets.length - 1; j >= 0; j--) {
      const b = bullets[j];
      if (Math.hypot(b.x - z.x, b.y - z.y) < z.radius + b.radius) {
        z.hp--;
        bullets.splice(j, 1);
        spawnParticles(z.x, z.y, "#6b8e23");
        break;
      }
    }

    if (z.hp <= 0) {
      zombies.splice(i, 1);
      score += 10;
      spawnParticles(z.x, z.y, "#8b0000");
      // Every 10 kills, the next wave gets harder.
      if (score % 100 === 0) {
        wave++;
        spawnInterval = Math.max(20, spawnInterval - 8);
      }
      continue;
    }

    // Zombie touches player
    if (Math.hypot(player.x - z.x, player.y - z.y) < player.radius + z.radius) {
      player.hp -= 0.4;
      if (player.hp <= 0) {
        player.hp = 0;
        gameOver = true;
      }
    }
  }

  // Particles
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.x += p.vx;
    p.y += p.vy;
    p.vx *= 0.92;
    p.vy *= 0.92;
    p.life--;
    if (p.life <= 0) particles.splice(i, 1);
  }
}

// ---- Draw ------------------------------------------------------------------
function draw() {
  // Background
  ctx.fillStyle = "#1a1f1a";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // Faint grid
  ctx.strokeStyle = "rgba(255,255,255,0.03)";
  ctx.lineWidth = 1;
  for (let x = 0; x < canvas.width; x += 50) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, canvas.height);
    ctx.stroke();
  }
  for (let y = 0; y < canvas.height; y += 50) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(canvas.width, y);
    ctx.stroke();
  }

  // Particles
  for (const p of particles) {
    ctx.globalAlpha = p.life / 25;
    ctx.fillStyle = p.color;
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;

  // Zombies
  for (const z of zombies) {
    ctx.fillStyle = "#6b8e23";
    ctx.beginPath();
    ctx.arc(z.x, z.y, z.radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#1a1f1a";
    ctx.beginPath();
    ctx.arc(z.x - 5, z.y - 3, 2.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(z.x + 5, z.y - 3, 2.5, 0, Math.PI * 2);
    ctx.fill();
  }

  // Bullets
  ctx.fillStyle = "#ffd54f";
  for (const b of bullets) {
    ctx.beginPath();
    ctx.arc(b.x, b.y, b.radius, 0, Math.PI * 2);
    ctx.fill();
  }

  // Player gun (rotated toward the mouse)
  const aim = Math.atan2(mouse.y - player.y, mouse.x - player.x);
  ctx.save();
  ctx.translate(player.x, player.y);
  ctx.rotate(aim);
  ctx.fillStyle = "#444";
  ctx.fillRect(0, -3, player.radius + 12, 6);
  ctx.restore();

  // Player body
  ctx.fillStyle = "#4fc3f7";
  ctx.beginPath();
  ctx.arc(player.x, player.y, player.radius, 0, Math.PI * 2);
  ctx.fill();

  // HUD: score and wave
  ctx.fillStyle = "#fff";
  ctx.font = "20px monospace";
  ctx.textAlign = "left";
  ctx.fillText("Score: " + score, 20, 34);
  ctx.fillText("Wave: " + wave, 20, 60);

  // HUD: health bar
  const barW = 200;
  const barX = canvas.width - barW - 20;
  ctx.fillStyle = "#400";
  ctx.fillRect(barX, 20, barW, 18);
  ctx.fillStyle = "#e53935";
  ctx.fillRect(barX, 20, barW * (player.hp / player.maxHp), 18);
  ctx.strokeStyle = "#fff";
  ctx.strokeRect(barX, 20, barW, 18);

  // Game over screen
  if (gameOver) {
    ctx.fillStyle = "rgba(0,0,0,0.7)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#fff";
    ctx.textAlign = "center";
    ctx.font = "48px monospace";
    ctx.fillText("GAME OVER", canvas.width / 2, canvas.height / 2 - 20);
    ctx.font = "24px monospace";
    ctx.fillText("Final Score: " + score, canvas.width / 2, canvas.height / 2 + 20);
    ctx.fillText("Press R or click to restart", canvas.width / 2, canvas.height / 2 + 56);
  }
}

// ---- Main loop -------------------------------------------------------------
function loop() {
  update();
  draw();
  requestAnimationFrame(loop);
}
loop();
