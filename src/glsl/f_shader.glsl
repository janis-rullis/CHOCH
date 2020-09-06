uniform float t;
uniform vec2 res;
uniform vec2 pos;
uniform vec2 speed;
// cam.xy = cam position, cam.zw - cam zoom
uniform vec4 cam;
// death factor
uniform float df;
// checkpoint factor
uniform float cf;

const float playerSize = 0.03;
// room size
const vec2 csize = vec2(1., 2.5);
const vec2 axis45 = vec2(1./sqrt(2.)), axis45N = axis45.yx*vec2(1.,-1.);

#define PI 3.14159265
#define LAYERS 6.0
#define NOISE_AMP 0.0

float hash(float x) {return fract(sin(x)*31345.23);}
float hash2(vec2 x) {return hash(dot(x, vec2(43.123, 32.12345)));}

// float linNoise(float x) {
//   return mix(hash(floor(x)), hash(floor(x)+1.), fract(x));
// }

float smoothNoise(float x) {
  return mix(hash(floor(x)), hash(floor(x)+1.), smoothstep(0.,1.,fract(x)));
}

// copied from iq's sdf functions
mat2 mr(float a) {float s=sin(a),c=cos(a);return mat2(c,s,-s,c);}

float sdBox(vec2 p, vec2 b) {
  vec2 d = abs(p)-b;
  return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

float sdCircle(vec2 p, float r) {return length(p)-r;}

float sdCross(vec2 p, vec2 size) {
  return min(
      sdBox(p, size),
      sdBox(p, size.yx)
  );
}

struct MapValue {
  float solid; // solid < 0 - point is solid (distance to closest solid)
  float deadly; // deadly and checkpoint work the same way
  float deadlyFactor; // > 0.5 - deadly zone on, < .5 - off
  float checkpoint;
  float checkpointId; // id of checkpoint, if checkpoint in current point
};

// gles 2 somehow doesn't support 1./0.
#define INF 1e10

float sawtooth(float t) {
  return 2.*(fract(t)-.5);
}

float asawtooth(float t) {return abs(sawtooth(t));}

float roomTest(vec2 p) {
  vec2 pdead = p - vec2(-0.3, -0.4);
  pdead *= mr(t);
  float deadly = sdCross(pdead, vec2(0.05, 0.45));

  pdead = p - vec2(0.3, 0.1);
  pdead *= mr(-t+PI/4.);
  deadly = min(deadly, sdCross(pdead, vec2(0.05, 0.45)));

  pdead = p - vec2(-0.3, 0.7);
  pdead *= mr(t+PI/8.);
  deadly = min(deadly, sdCross(pdead, vec2(0.05, 0.45)));

  return deadly;
}

float roomLasers(vec2 p) {
  float scale = .5;
  vec2 axes[3];
  axes[0] = vec2(0., 1.);
  axes[1] = axis45;
  axes[2] = axis45N;
  float deadly = INF;
  for (int i=0;i<3;++i) {
    float pdot = dot(p, axes[i]) + t/32.;
    float pfr = abs(mod(pdot, scale) - scale/2.);
    float fl = floor(pdot*scale);
    float s = sin(t*2. + pdot*2. + .66*PI*float(i));
    deadly = min(deadly, pfr + scale/16.* (s+.5));
  }
  return deadly;
}

float roomSines1(vec2 p) {
  float mult = 10.;
  float dead = sin(p.x*mult) * sin(p.y*mult) + .7*sin(2.*t + 5.*p.y + 10.*p.x) + .5;
  return dead/mult;
}

float roomSines2(vec2 p) {
  float mult = 10.;
  float dead = sin(p.x*mult) * sin(p.y*mult) + .7*sin(2.*t + 5.*p.y + sin(.3*t)) + .4;
  return dead/mult;
}

float roomPolar1(vec2 p) {
  p = vec2(length(p), atan(p.y, p.x));
  float lenMul = 3.;
  float l = p.x*lenMul-t/2.;
  float rotDirection = mod(floor(l),2.) == 0. ? -1. : 1.;
  float holes = (asawtooth(p.y/PI*3. - t/4. * rotDirection)-.7)*p.x;
  float deadly = max((asawtooth(l) - .2)/lenMul, holes);
  return deadly;
}

float roomCircleInv(vec2 p) {
  float d = dot(p, p);
  p /= d;
  vec2 size = vec2(1., 2.5);
  p.y += .5*t;
  vec2 cell = floor(p/size);
  p.x += .7*t* mix(-1.,1.,mod(cell.y, 2.));
  vec2 mp = abs(mod(p, size) - size/2.)-size/2.5;
  cell = floor(p/size);
  float iscell = step(.5,mod(cell.x+cell.y, 2.));
  float deadly = mix(max(mp.x, mp.y), 1000., iscell);
  return deadly * d;
}

float roomPotential(vec2 p) {
  float pot = 0.;
  const float I = 4.;
  for(float i=0.;i<I;++i) {
    vec2 off = vec2(0., mix(-.9,.9,i/(I-1.)));
    off.y += .22*sin(t + PI/2.*i);
    off.x += .1*sin(t + PI/3.*i);
    pot += 1. / length(p-off);
  }
  float potInv = 1./(pot);
  float modSize = .03;
  float deadly = max(.09-potInv, abs(mod(potInv-t/30., modSize)-modSize/2.)-modSize/2.3);
  return deadly;
}

float roomRandomWaves(vec2 p) {
  float sz = .3;
  float factor = (sin(t)+1.)/2.;
  p.y -= t/6.;
  p.x += factor*smoothNoise(p.y*5.+123. + t) * .5;
  p.y += factor*smoothNoise(p.x*5. + .4*t) * .4;
  return abs(mod(p.y, sz) - sz/2.)-sz/20.;
}

float roomFractal1(vec2 p) {
  const float I = 3.;
  for (float i=0.;i<I;++i) {
    p.x = abs(p.x);
    p.x -= .3;
    p.y -= .1;
    p = p*mr(2.*PI/I);
  }
  
  float s = 0.4;
  p.y -= t/10.;
  p.x -= t/20.;
  vec2 mp = abs(mod(p, s)-s/2.)-s/3.;
  return max(mp.x, mp.y);
}

// seems unpassable, but maybe I could fix it...
float roomFractal2(vec2 p) {
  const float I = 6.;
  for (float i=0.;i<I;++i) {
    p.x = abs(p.x);
    p.x -= .3;
    p.y += .1;
    p *= mr(2.*PI/I);
  }
  p *= mr(PI/3.);
  
  float s = 0.4;
  p.y -= t/10.;
  p.x -= t/20.;
  vec2 mp = abs(mod(p, s)-s/2.)-s/3.;
  return max(mp.x, mp.y);
}

float roomBoxesTrace(vec2 p) {
  vec2 size = vec2(.2);
  vec2 mp = mod(p, size)-size/2.;
  vec2 cell = floor(p/size);
  vec2 sst = vec2(0.);
  vec2 cellDiv = vec2(5., 30.);
  cell.x += .5;
  float f = .5 +
    (.25*sin(1.*cell.y - t) +
    .75*sin(.8*cell.x + 2.*sin(t))
    ) *.5;
  mp *= mr((1.-f)*PI);
  return sdBox(mp, mix(vec2(-.05),size/2.1, f));
}

float roomCirclesSizeMod(vec2 p) {
  p *= mr(PI/4.);
  float size = .3;
  vec2 mp = mod(p, size)-size/2.;
  vec2 cell = floor(p/size);
  
  vec2 circleSizes = vec2(size/32., size/2.55);
  float field1 = sdCircle(mp, mix(circleSizes.x, circleSizes.y, sin(t)*.5+.5));
  mp = mod(p+size/2., size)-size/2.;
  float field2 = sdCircle(mp, mix(circleSizes.x, circleSizes.y, sin(t+PI)*.5+.5));
  return min(field1, field2);
}

float roomBoxes(vec2 p) {
  float size = 0.15;
  vec2 p1 = vec2(abs(p.x), mod(p.y, size) - size/2.);
  float yFloor = floor(p.y/size);
  float freq = .5 + yFloor * size * 3.;//mix(1., 3., hash(yFloor));
  return max(abs(p1.y)-size/3., .2+.2*sin(freq*t + 123.)-p1.x);
}

float roomBoxes2(vec2 p) {
  float size = 0.1;
  vec2 p1 = vec2(p.x, mod(p.y, size) - size/2.);
  float yFloor = floor(p.y/size);
  float freq = .5 + yFloor * 1.;//mix(1., 3., hash(yFloor));
  return sdBox(p1 - vec2(.41*sin(10.*yFloor + t), 0.), vec2(.1, size/2.2));
}

float roomBoxes3(vec2 p) {
  float size = .3;
  vec2 p1 = vec2(p.x, mod(p.y, size) - size/2.);
  float yFloor = floor(p.y/size);
  float sizey = size;
  size = .28 +.1*hash(yFloor + 10.3);
  float dir = mix(-1.,1.,mod(yFloor, 2.));
  float speed = dir * (.2+hash(yFloor)*.1);
  p1.x = mod(p1.x + speed*t, size) - size/2.;
  return sdBox(p1, vec2(.01, sizey/2.1));
}

float roomPolarMod(vec2 p) {
  const float I = 3.;
  p.x = -p.x;
  float f = smoothstep(0., 1., fract(t)) *2.*PI/I;
  p *= mr(f);
  vec2 pp = vec2(length(p), atan(p.y, p.x));
  pp.y = mod(pp.y, 2.*PI/I) - PI/I;
  p = vec2(pp.x*cos(pp.y), pp.x*sin(pp.y)) - vec2(.37, 0.);
  p *= mr(-I*f);
  return sdBox(p, vec2(0.06));
}

float roomPolarMod2(vec2 p) {
  float deadly = INF;
  float boxSize = 0.05;
  for(float i=0.;i<3.;++i) {
    float boxOff = .2 * (i+1.);
    vec2 p1 = p;
    p1 *= mr(t/2. * mix(-1.,1.,mod(i, 2.)));
    float I = floor(2.*boxOff/boxSize);
    vec2 pp = vec2(length(p1), atan(p1.y, p1.x));
    float angFloor = floor(pp.y / (2.*PI/I));
    pp.y = mod(pp.y, 2.*PI/I) - PI/I;
    p1 = vec2(pp.x*cos(pp.y), pp.x*sin(pp.y)) - vec2(boxOff, 0.);
    vec2 sz = vec2(boxSize);
    sz *= sin(angFloor + t)*.7+.3;
    deadly = min(deadly, sdBox(p1, sz));
  }
  return deadly;
}

float roomMovingCorridor(vec2 p) {
  float tmult = 1., ymult = 3.;
  float noise1 = smoothNoise(p.y*ymult + 123.*floor(tmult*t) - t);
  float noise2 = smoothNoise(p.y*ymult + 123.*floor(tmult*t+1.) - t);
  p.x += .3*(mix(noise1, noise2, smoothstep(0., 1., fract(tmult*t)))-.5);
  return .1 - abs(p.x);
}

vec2 roomSolidWait(vec2 p) {
  float ysize = 1.5, corrWidth = .3;
  vec2 sp = p;
  sp.y += 0.5 * ysize * step(0.,sp.x);
  sp.y = mod(sp.y, ysize) - ysize/2.;
  sp.x = abs(sp.x);
  float solid = abs(p.x) - corrWidth;
  solid = min(solid, sdBox(sp - vec2(corrWidth+0.03, 0.), vec2(.1)));
  
  vec2 dp = p;
  dp.y = mod(dp.y+.5, ysize/2.) - ysize / 4.;
  vec2 deadlyBoxSize = mix(vec2(.1), vec2(.29, .5), smoothstep(0.1, 0.5, sin(t*1.2)));
  float deadly = sdBox(dp, deadlyBoxSize);
  return vec2(-solid, deadly);
}

vec2 mixCheckpoint(vec2 checkpoint, vec2 new, ivec2 room, ivec2 inRoom) {
  return mix(checkpoint, 
    mix(checkpoint, new, step(new.x, checkpoint.x)),
    all(equal(room, inRoom)) ? 1. : 0.
  );
}

MapValue map(vec2 p) {
  float row = floor(p.y/csize.y);
  ivec2 cid = ivec2(floor(p/csize));
  vec2 p1 = mod(p, csize) - csize/2.;
  MapValue val;
  
  bool isRoom = true;
  // room.x - solids (additional to room bounds), room.y - deadly objects, room.z - deadly factor
  vec3 room = vec3(INF, INF, 1.);
  if (cid.x == 0) {
    if (cid.y == 0) room.y = roomTest(p1);
    else if (cid.y == 1) room.y = roomLasers(p1);
    else if (cid.y == 2) room.y = roomSines1(p1);
    else if (cid.y == 3) room.y = roomSines2(p1);
    else if (cid.y == 4) room.y = roomPolar1(p1);
    else if (cid.y == 5) room.y = roomCircleInv(p1);
    else if (cid.y == 6) room.y = roomPotential(p1);
    else if (cid.y == 7) room.y = roomRandomWaves(p1);
    else if (cid.y == 8) room.y = roomFractal1(p1);
    else if (cid.y == 9) room.y = roomFractal2(p1);
    else if (cid.y == 10) room.y = roomBoxesTrace(p1);
    else if (cid.y == 11) room.y = roomCirclesSizeMod(p1);
    else if (cid.y == 12) room.y = roomBoxes(p1);
    else if (cid.y == 13) room.y = roomBoxes2(p1);
    else if (cid.y == 14) room.y = roomBoxes3(p1);
    else if (cid.y == 15) room.y = roomPolarMod(p1);
    else if (cid.y == 16) room.y = roomPolarMod2(p1);
    else if (cid.y == 17) room.y = roomMovingCorridor(p1);
    else if (cid.y == 18) room.xy = roomSolidWait(p1);
    else isRoom = false;
  } else {
    isRoom = false;
  }

  MapValue v = MapValue(-INF, room.y, room.z, INF, 0.);
  if(isRoom) {
    float roomBox = sdBox(p1, csize/2.2);
    v.deadly = max(v.deadly, roomBox);
    v.solid = min(-roomBox, room.x);
  }

  vec2 corrY = vec2(-1., 19. * csize.y); // 19 - rooms count, corrY.x - corridor bottom, corrY.y - corridor top
  corrY = vec2((corrY.x + corrY.y)/2., (corrY.y - corrY.x)/2.);
  float corridor = max(abs(p.x-.5)-.1, abs(p.y - corrY.x) - corrY.y);
  v.solid = max(v.solid, -corridor);
  
  // checkpoints
  float cpy = mod(p.y + csize.y/2., csize.y) - csize.y/2.;
  v.checkpoint = abs(cpy) - .03;
  v.checkpointId = floor((p.y + csize.y/2.) / csize.y);
  
  return v;
}

vec2 normal(vec2 p) {
    vec2 E=vec2(0.001, 0.);
    float m = map(p).solid;
    return normalize(vec2(
        map(p+E.xy).solid - m,
        map(p+E.yx).solid - m
    ));
}

float drawLaserBounds(float p, float strength) {
  return pow(0.001 * strength / abs(p), 2.5);
}

vec3 renderLayer(vec2 uv) {
  MapValue m = map(uv);
  vec3 c = vec3(0.);
  if(m.solid > 0.) {
    vec3 checkpointColor = vec3(0.1, 1., 0.1);
    c += drawLaserBounds(m.checkpoint, 3.) * checkpointColor;
    if (m.checkpoint < 0.) {
      c += checkpointColor/10.;
    }
    else {
      vec3 deadlyColor = mix(vec3(.1,.1,.1), vec3(1.,.1,.1), vec3(step(.5, m.deadlyFactor)));
      c += drawLaserBounds(m.deadly, 3.) * deadlyColor;
      if (m.deadly < 0.) c += deadlyColor/10.;
    }
  }
  // if (m.solidDisplay > 0.) {
  //   c += m.solidDisplay;
  // }
  c += drawLaserBounds(m.solid, 2.);
  //if (m.solid < 0.) c += m.solidDisplay;
  return c;
}

float sdSegment( in vec2 p, in vec2 a, in vec2 b ) {
    vec2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}

float sdPosCircle(vec2 p, float r) {
  return max(0., length(p)-r);
}

float renderSpider(vec2 uv) {
  float radius = playerSize;
  float c = 0.;

  uv -= pos;
  float spiderAngle = atan(speed.y, speed.x);

  // draw body
  float bodyRadius = radius / 3.;
  vec2 uvBody = uv - vec2(0., (sin(4.*t)+1.) * radius / 16. + radius / 3.);
  c += pow(radius/100. / sdPosCircle(uvBody, bodyRadius), 2.);

  // draw legs
  vec2 spiderDirUp = vec2(cos(spiderAngle), sin(spiderAngle));
  for(float i=0.; i<8.; ++i) {
    float ang = mix(-PI/4., PI/4., mod(i, 4.)/3.) + step(4., i) * PI - PI/2. + spiderAngle;
    vec2 legOffset = 0.9*radius*vec2(cos(ang), sin(ang));
    legOffset += radius * 0.1 *spiderDirUp * sin(20.*t + (mod(i,2.)==0. ? PI: 0.)) * length(speed);
    // legs ends (circles)
    //c += pow(radius/100. / sdPosCircle(uv + legOffset, radius/16.), 2.);

    // legs sticks
    vec2 uvSeg = uv;
    float r = clamp(0., 1., length(uv) / radius);
    uvSeg.y -= 0.01*(r-r*r);
    //uvSeg += (vec2(linNoise(r*10.-10.*t), linNoise(r*10.+15.-15.*t))-.5) * radius * 0.1;
    //c += pow(radius/200. / sdSegment(uvSeg, uv-uvBody, -legOffset), 1.2);

    c += drawLaserBounds(sdSegment(uvSeg, uv-uvBody, -legOffset), r*2.);
  }
  c = min(1., c);

  // draw eyes
  uvBody *= mr(spiderAngle);
  uvBody.y = abs(uvBody.y);
  c -= pow(radius/100. / sdPosCircle(uvBody -
    vec2(1.,0.) * bodyRadius * 0.7 -
    vec2(0.,1.) * bodyRadius * 0.3, radius / 40.), 2.);

  return c;
}

vec3 renderAll(vec2 uv) {
  vec3 c = vec3(0.);
  uv /= cam.zw;
  for (float i = 0.; i<LAYERS; ++i) {
    float layerOffset = i/LAYERS*0.04;
    vec2 uv1 = uv * (1.0-layerOffset) - vec2(0., layerOffset)
      + vec2(hash2(uv+i+t)-.5, hash2(1.3*uv+i+1.4*t)-.5)*NOISE_AMP;
    uv1 = uv1 + cam.xy;

    c += renderLayer(uv1) / LAYERS;
    if (i ==0.) {
      // debug collider
      //c = mix(c, vec3(0.,0.,0.1), step(length(uv1 - pos), playerSize));
      c += renderSpider(uv1);
    }
  }
  return c;
}

void main() {
    // pixel 1 - collision check + normal
    if (gl_FragCoord.x < 1. && gl_FragCoord.y < 1.) {
        float solid = map(pos).solid;
        gl_FragColor = vec4(solid < playerSize ? vec3(1., 0.5*(normal(pos)+1.)) : vec3(0.), 1.);
    } else
    // pixel 2 - death check
    if (gl_FragCoord.x < 2. && gl_FragCoord.y < 1.) {
        gl_FragColor = vec4(vec3(map(pos).deadly < playerSize/2. ? 1. : 0.), 1.);
    } else
    // pixel 3 - checkpoint check
    if (gl_FragCoord.x < 3. && gl_FragCoord.y < 1.) {
        MapValue m = map(pos);
        gl_FragColor = vec4(m.checkpoint < 0. ? vec3(1., m.checkpointId/255., 0.) : vec3(0.), 1.);
    } else {
        vec2 uv = 2. * gl_FragCoord.xy / res - 1.;
        uv.x *= res.x / res.y;

        float aberrationSize = 0.01;
        vec3 c = vec3(
          renderAll(uv-vec2(aberrationSize,0.)).r,
          renderAll(uv).g,
          renderAll(uv+vec2(aberrationSize,0.)).b
        );

        gl_FragColor = vec4(sqrt(c)+vec3(df,cf,0.), 1.0);
    }
}