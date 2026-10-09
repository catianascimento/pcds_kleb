import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  allowedDevOrigins: ["localhost", "127.0.0.1", "172.16.20.106", '172.16.20.233'],
};

export default nextConfig;
