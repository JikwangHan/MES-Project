# MES Project

MES(Project) 저장소입니다. 이 문서는 **처음 GitHub를 쓰는 초보자**도 따라 할 수 있도록 단계별로 설명합니다. 아래 안내만 그대로 따라 하면 프로젝트를 내려받고, 간단한 예제 서버를 실행해 볼 수 있습니다.

## 1) 준비물
- Git: https://git-scm.com 에서 설치 (기본 설정 그대로 Next를 눌러도 됩니다)
- 코드 편집기: Visual Studio Code 추천
- Node.js 18 이상(예제 서버 실행용): https://nodejs.org 에서 LTS 버전 설치

## 2) 프로젝트 내려받기
PowerShell(또는 명령 프롬프트)을 열고 아래 명령을 입력합니다.
```bash
git clone https://github.com/JikwangHan/MES-Project.git
cd MES-Project
```
정상적으로 내려받으면 `MES-Project` 폴더 안에 `README.md`와 `src` 폴더가 보입니다.

## 3) 폴더 구조 미리보기
```
MES-Project/
├─ README.md              # 이 문서
├─ .gitignore             # Git에 올리지 않을 파일 목록
└─ src/
   └─ example-server.js   # 간단한 예제 서버(바로 실행 가능)
```

## 4) 바로 실행해보는 예제 (Node.js 내장 http 사용)
아래 단계는 “서버가 제대로 동작하는지” 확인하는 가장 단순한 예시입니다.

1. 프로젝트 폴더로 이동: `cd MES-Project`
2. 서버 실행: `node src/example-server.js`
3. PowerShell 화면에 `Server running at http://localhost:4000` 이 보이면 성공입니다.
4. 웹 브라우저 주소창에 `http://localhost:4000` 입력 → “MES Project 서버가 정상 동작 중입니다.” 문구가 보이면 OK.

### 예제 서버 코드 살펴보기
`src/example-server.js` 파일에 들어 있는 코드입니다. 그대로 실행만 해도 되고, 메시지를 바꾸면서 테스트해도 됩니다.
```javascript
const http = require('http');

const PORT = 4000;

const server = http.createServer((req, res) => {
  // 간단한 텍스트 응답
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('MES Project 서버가 정상 동작 중입니다.');
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
```

## 5) 자주 쓰는 Git 명령 (초보자용)
- 변경 사항 확인: `git status`
- 파일 추가/갱신 상태 확인: `git status -sb` (요약)
- 새 파일 스테이징: `git add 파일명`
- 커밋 만들기: `git commit -m "메시지"`
- GitHub로 올리기: `git push origin main` (처음 푸시하는 경우 브랜치 이름을 확인하세요. 기본은 `main`)

## 6) 다음 단계 제안
- 프로젝트 목표와 요구사항을 정리한 문서 추가 (예: `docs/requirements.md`)
- 백엔드/프론트엔드 선택 후 폴더 구조 잡기 (예: `backend/`, `frontend/`)
- 테스트 자동화 도입 (예: Jest, Vitest, Pytest 등 스택에 맞춰 선택)

필요한 스택이나 세부 구조를 알려주시면, 거기에 맞춘 설정 파일과 예제 코드를 더 추가해드리겠습니다.
