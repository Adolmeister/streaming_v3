import { AuthClient } from '@dfinity/auth-client';
import { HttpAgent } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';

let authClient;
let agent;
let backendCanisterId = process.env.CANISTER_ID_BACKEND;
let tokenCanisterId = process.env.CANISTER_ID_TOKEN;
let identity;

async function init() {
    authClient = await AuthClient.create();
    
    if (await authClient.isAuthenticated()) {
        identity = authClient.getIdentity();
        agent = new HttpAgent({ identity });
        await updateUI();
    } else {
        agent = new HttpAgent();
    }
    
    if (process.env.DFX_NETWORK !== "ic") {
        await agent.fetchRootKey();
    }
    
    setupEventListeners();
    await loadVideos();
}

async function login() {
    const identityProviderUrl = process.env.DFX_NETWORK === "local" 
        ? `http://localhost:4943/?canister=rdmx6-jaaaa-aaaaa-aaadq-cai`
        : "https://identity.ic0.app";
    
    await authClient.login({
        identityProvider: identityProviderUrl,
        onSuccess: async () => {
            identity = authClient.getIdentity();
            agent = new HttpAgent({ identity });
            if (process.env.DFX_NETWORK !== "ic") {
                await agent.fetchRootKey();
            }
            await updateUI();
        }
    });
}

async function callBackend(methodName, args = []) {
    const response = await agent.call(Principal.fromText(backendCanisterId), {
        methodName,
        arg: new Uint8Array(args)
    });
    return response;
}

async function uploadVideo() {
    const fileInput = document.getElementById('video-file');
    const titleInput = document.getElementById('video-title');
    const progressDiv = document.getElementById('upload-progress');
    
    if (!fileInput.files[0] || !titleInput.value) {
        alert('Please select a file and enter a title');
        return;
    }
    
    const file = fileInput.files[0];
    const title = titleInput.value;
    const videoId = Date.now().toString();
    
    const chunkSize = 1024 * 1024;
    const chunks = Math.ceil(file.size / chunkSize);
    
    progressDiv.innerHTML = `Uploading... 0/${chunks} chunks`;
    progressDiv.style.display = 'block';
    
    for (let i = 0; i < chunks; i++) {
        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const chunk = file.slice(start, end);
        
        const arrayBuffer = await chunk.arrayBuffer();
        const uint8Array = new Uint8Array(arrayBuffer);
        
        try {
            await callBackend('uploadVideoChunk', [
                videoId,
                title,
                Array.from(uint8Array),
                i,
                file.type
            ]);
            
            progressDiv.innerHTML = `Uploading... ${i + 1}/${chunks} chunks`;
        } catch (error) {
            alert('Upload failed: ' + error.message);
            return;
        }
    }
    
    progressDiv.innerHTML = 'Upload completed!';
    await loadVideos();
    
    fileInput.value = '';
    titleInput.value = '';
}

async function loadVideos() {
    try {
        const videos = await callBackend('getVideos');
        const grid = document.getElementById('videos-grid');
        
        grid.innerHTML = '';
        
        videos.forEach(video => {
            const videoCard = document.createElement('div');
            videoCard.className = 'video-card';
            videoCard.innerHTML = `
                <h3>${video.name}</h3>
                <p>Views: ${video.views}</p>
                <p>Size: ${(video.totalSize / 1024 / 1024).toFixed(2)} MB</p>
                <p>Type: ${video.fileType}</p>
                <button onclick="playVideo('${video.id}')">Play & Earn DFW</button>
            `;
            grid.appendChild(videoCard);
        });
    } catch (error) {
        console.error('Failed to load videos:', error);
    }
}

window.playVideo = async function(videoId) {
    if (!identity) {
        alert('Please login first');
        return;
    }
    
    try {
        const sessionResult = await callBackend('startViewSession', [videoId]);
        
        if (sessionResult.ok) {
            const sessionId = sessionResult.ok;
            
            const watchTime = 5000;
            
            alert(`Playing video... Watch for ${watchTime/1000} seconds to earn DFW!`);
            
            setTimeout(async () => {
                try {
                    await callBackend('completeViewSession', [sessionId]);
                    alert('Video completed! Uploader earned DFW tokens!');
                    await updateBalance();
                } catch (error) {
                    console.error('Failed to complete session:', error);
                }
            }, watchTime);
        } else {
            alert('Failed to start viewing session: ' + sessionResult.err);
        }
    } catch (error) {
        alert('Error playing video: ' + error.message);
    }
};

async function updateUI() {
    if (identity) {
        document.getElementById('connect-btn').style.display = 'none';
        document.getElementById('balance-info').style.display = 'block';
        await updateBalance();
    }
}

async function updateBalance() {
    if (identity) {
        try {
            const balance = await callBackend('getUserBalance');
            document.getElementById('balance').textContent = (balance / 100000000).toFixed(2);
        } catch (error) {
            console.error('Failed to get balance:', error);
        }
    }
}

function setupEventListeners() {
    document.getElementById('connect-btn').addEventListener('click', login);
    document.getElementById('upload-btn').addEventListener('click', uploadVideo);
}

init();
