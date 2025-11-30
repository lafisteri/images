# 🖥 Chrome & Chromedriver with VNC

A ready-to-use Docker image for running **Google Chrome + Chromedriver + VNC**, fully compatible with **Selenoid**.

---

## 🎯 Purpose

This project continues the idea of the abandoned **aerokube/images** repository  
and provides **up-to-date, maintained browser images** designed for:

- **Selenoid**
- **Selenium Grid**
- **Docker-based test automation**
- **CI/CD pipelines**
- **Kubernetes environments**

Its main goal is to offer a reliable, actively maintained alternative to outdated browser images, while staying fully compatible with the existing Selenoid ecosystem.

---

## 🚀 Local image build

The `./images` script automates the build and accepts the following arguments:

| Argument     | Description               |
|--------------|----------------------------|
| `-b`         | Chrome `.deb` version      |
| `-d`         | Chromedriver version       |
| `-t`         | Final Docker image tag     |
| `vnc_chrome` | Enables the VNC stack      |

### Build example

```bash
./images chrome -b 142.0.7444.61-1 -d 142.0.7444.61 -t my/chrome:142.0 vnc_chrome
```

---

## 🧩 Example Selenoid config

Below is a minimal configuration example showing how to use this image with Selenoid  
(you can replace version numbers with any supported version):

```json
{
  "chrome": {
    "default": "142.0",
    "versions": {
      "142.0": {
        "image": "lafisteri/images:142.0",
        "port": "4444",
        "path": "/"
      }
    }
  }
}
```

## 📊 Download Statistics

### Chrome: [![Chrome Docker Pulls](https://img.shields.io/docker/pulls/selenoid/chrome.svg)](https://hub.docker.com/r/lafisteri/images)

---

## 📄 License

This project is licensed under the **Apache License 2.0**.

You are free to use, modify, and distribute this project in both open-source
and commercial environments. See the [LICENSE](./LICENSE) file for full terms.

This project is an independent open-source initiative and is fully compatible 
with common browser automation tools.
