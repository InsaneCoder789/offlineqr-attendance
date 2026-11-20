"use client";

import { useEffect, useRef } from "react";
import styles from "./story.module.css";

export function ClassroomScene() {
  const mount = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const host = mount.current;
    if (!host) return;
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    let disposed = false;
    let cleanup: (() => void) | undefined;
    async function start() {
      if (motion.matches || !host) return;
      const THREE = await import("three");
      if (disposed || motion.matches) return;
      const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(40, 1, .1, 20);
      camera.position.z = 4;
      const geometry = new THREE.PlaneGeometry(1, 1);
      const material = new THREE.MeshBasicMaterial();
      const plate = new THREE.Mesh(geometry, material);
      scene.add(plate);
      let ready = false;
      let visible = true;
      let frame = 0;
      const draw = () => {
        frame = 0;
        if (!ready || !visible || disposed || motion.matches) return;
        const bounds = host.getBoundingClientRect();
        const progress = Math.min(1, Math.max(0, -bounds.top / Math.max(1, bounds.height)));
        plate.position.y = progress * .04;
        plate.rotation.y = progress * .07;
        renderer.render(scene, camera);
      };
      const schedule = () => { if (!frame) frame = requestAnimationFrame(draw); };
      const resize = () => {
        const { clientWidth: width, clientHeight: height } = host;
        if (!width || !height) return;
        camera.aspect = width / height;
        camera.updateProjectionMatrix();
        const viewHeight = 2 * camera.position.z * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
        const viewWidth = viewHeight * camera.aspect;
        const imageHeight = Math.max(viewHeight, viewWidth / 2) * 1.03;
        const imageWidth = imageHeight * 2;
        plate.scale.set(imageWidth, imageHeight, 1);
        plate.position.x = (viewWidth - imageWidth) * .10;
        renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
        renderer.setSize(width, height);
        schedule();
      };
      const source = matchMedia("(max-width: 600px)").matches ? "/branding/classroom-mobile.webp" : "/branding/classroom-hd.webp";
      const texture = new THREE.TextureLoader().load(source, loaded => {
        if (disposed) return;
        loaded.colorSpace = THREE.SRGBColorSpace;
        material.map = loaded;
        material.needsUpdate = true;
        ready = true;
        schedule();
      });
      const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; schedule(); });
      observer.observe(host);
      const dimensions = new ResizeObserver(resize);
      dimensions.observe(host);
      renderer.domElement.addEventListener("webglcontextlost", () => renderer.domElement.remove());
      host.append(renderer.domElement);
      window.addEventListener("scroll", schedule, { passive: true });
      const preference = () => { renderer.domElement.hidden = motion.matches; schedule(); };
      motion.addEventListener("change", preference);
      resize();
      cleanup = () => {
        cancelAnimationFrame(frame);
        observer.disconnect();
        dimensions.disconnect();
        window.removeEventListener("scroll", schedule);
        motion.removeEventListener("change", preference);
        geometry.dispose();
        material.dispose();
        texture.dispose();
        renderer.dispose();
        renderer.domElement.remove();
      };
    }
    void start().catch(() => {});
    return () => { disposed = true; cleanup?.(); };
  }, []);
  return <div ref={mount} className={styles.classroomScene} aria-hidden="true" />;
}
