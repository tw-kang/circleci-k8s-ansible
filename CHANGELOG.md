# 📝 변경 이력

## v2.1.0 (2024-12-19)

### 📚 문서 개선
- **중복 제거**: 7개 문서를 3개로 통합하여 중복 내용 제거
- **역할 명확화**: 각 문서의 목적과 대상 사용자 명확히 구분
- **사용성 향상**: 문서 간 참조 체계 개선

### 🔄 문서 구조 변경
- ✅ **유지**: `README.md` - 핵심 개요와 빠른 참조
- ✅ **유지**: `GETTING_STARTED.md` - 처음 사용자를 위한 완전 가이드 (20분)
- ✅ **유지**: `QUICK_START.md` - 기존 사용자를 위한 빠른 시작 (5분)  
- ✅ **유지**: `SECURITY_SETUP.md` - 고급 사용자를 위한 보안 가이드
- ❌ **제거**: `SETUP_CHECKLIST.md` - GETTING_STARTED.md와 중복
- ❌ **제거**: `WORKER_NODE_SETUP.md` - 스크립트 자동화로 불필요
- ❌ **제거**: `CIRCLECI_HELM_SETUP.md` - 구현 세부사항으로 불필요
- ❌ **제거**: `PACKAGE_MANAGEMENT.md` - 내부 구현 정보로 불필요

### 📖 문서별 개선사항

#### README.md
- 핵심 기능과 빠른 참조에 집중
- 문서 가이드 테이블 추가
- 프로젝트 구조 업데이트

#### GETTING_STARTED.md  
- 처음 사용자를 위한 완전한 20분 가이드
- 4단계 구조로 명확히 구성
- 현재 프로젝트 상태 반영

#### QUICK_START.md
- 기존 사용자를 위한 5분 빠른 가이드
- 3단계 원클릭 실행으로 간소화
- 핵심 배포 모드만 포함

#### SECURITY_SETUP.md
- 고급 사용자를 위한 완전한 보안 가이드
- 프로덕션 환경 보안 설정 집중
- 실용적인 보안 스크립트 제공

### 🎯 문서 사용법

| 상황 | 추천 문서 | 소요 시간 |
|------|-----------|-----------|
| 처음 프로젝트 사용 | GETTING_STARTED.md | 20분 |
| 빠른 재설치/재배포 | QUICK_START.md | 5분 |
| 보안 강화 필요 | SECURITY_SETUP.md | 15분 |
| 기능 확인/참조 | README.md | 2분 |

---

## v2.0.0 (2024-12-19)

### 🔧 주요 기능 개선
- 동적 Join Token 생성으로 24시간 만료 문제 해결
- PATH 환경변수 개선으로 Kubernetes 명령어 안정성 향상
- Kubernetes 도구 설치 검증 스크립트 추가
- SSH 비밀번호 Vault 연동 간소화
- 노드 추가 순서 최적화

### 🚀 새로운 기능
- `verify-k8s-tools.sh` 스크립트 추가
- 설치 시 검증 기능 통합
- 환경별 inventory 지원 (staging/production)

### 📊 지원 환경
- Kubernetes: v1.28.15
- containerd: v1.7.27
- 지원 OS: Rocky Linux 8, CentOS 8, RHEL 8, AlmaLinux 8
- 지원 아키텍처: x86_64, ARM64 (aarch64) 