import Array "mo:base/Array";
import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Option "mo:base/Option";

import Token "canister:token";

actor Backend {
  
  type FileChunk = {
    chunk : Blob;
    index : Nat;
  };

  type Video = {
    id : Text;
    name : Text;
    chunks : [FileChunk];
    totalSize : Nat;
    fileType : Text;
    uploader : Principal;
    uploadTime : Int;
    views : Nat;
  };

  type ViewSession = {
    viewer : Principal;
    video_id : Text;
    start_time : Int;
    completed : Bool;
  };

  private stable var videosEntries : [(Text, Video)] = [];
  private stable var userVideosEntries : [(Principal, [Text])] = [];
  private stable var viewSessionsEntries : [(Text, ViewSession)] = [];
  
  private var videos = HashMap.fromIter<Text, Video>(videosEntries.vals(), videosEntries.size(), Text.equal, Text.hash);
  private var userVideos = HashMap.fromIter<Principal, [Text]>(userVideosEntries.vals(), userVideosEntries.size(), Principal.equal, Principal.hash);
  private var viewSessions = HashMap.fromIter<Text, ViewSession>(viewSessionsEntries.vals(), viewSessionsEntries.size(), Text.equal, Text.hash);
  
  private stable var rewardPerView : Nat = 100000000;

  system func preupgrade() {
    videosEntries := Iter.toArray(videos.entries());
    userVideosEntries := Iter.toArray(userVideos.entries());
    viewSessionsEntries := Iter.toArray(viewSessions.entries());
  };

  system func postupgrade() {
    videosEntries := [];
    userVideosEntries := [];
    viewSessionsEntries := [];
  };

  public shared(msg) func uploadVideoChunk(
    videoId : Text, 
    name : Text, 
    chunk : Blob, 
    index : Nat, 
    fileType : Text
  ) : async Result.Result<(), Text> {
    
    let uploader = msg.caller;
    let fileChunk = { chunk = chunk; index = index };

    switch (videos.get(videoId)) {
      case null {
        let video = { 
          id = videoId;
          name = name; 
          chunks = [fileChunk]; 
          totalSize = chunk.size(); 
          fileType = fileType;
          uploader = uploader;
          uploadTime = Time.now();
          views = 0;
        };
        videos.put(videoId, video);
        
        let userVideoList = Option.get(userVideos.get(uploader), []);
        userVideos.put(uploader, Array.append(userVideoList, [videoId]));
        
        #ok(());
      };
      case (?existingVideo) {
        let updatedChunks = Array.append(existingVideo.chunks, [fileChunk]);
        let updatedVideo = {
          existingVideo with 
          chunks = updatedChunks;
          totalSize = existingVideo.totalSize + chunk.size();
        };
        videos.put(videoId, updatedVideo);
        #ok(());
      };
    };
  };

  public shared(msg) func startViewSession(videoId : Text) : async Result.Result<Text, Text> {
    let viewer = msg.caller;
    let sessionId = videoId # "_" # Principal.toText(viewer) # "_" # Int.toText(Time.now());
    
    switch (videos.get(videoId)) {
      case null { #err("Video not found") };
      case (?video) {
        if (Principal.equal(video.uploader, viewer)) {
          #err("Cannot view your own video")
        } else {
          let session = {
            viewer = viewer;
            video_id = videoId;
            start_time = Time.now();
            completed = false;
          };
          viewSessions.put(sessionId, session);
          #ok(sessionId);
        };
      };
    };
  };

  public shared(msg) func completeViewSession(sessionId : Text) : async Result.Result<(), Text> {
    let viewer = msg.caller;
    
    switch (viewSessions.get(sessionId)) {
      case null { #err("Session not found") };
      case (?session) {
        if (not Principal.equal(session.viewer, viewer)) {
          #err("Unauthorized")
        } else if (session.completed) {
          #err("Session already completed")
        } else {
          let completedSession = { session with completed = true };
          viewSessions.put(sessionId, completedSession);
          
          switch (videos.get(session.video_id)) {
            case null { #err("Video not found") };
            case (?video) {
              let updatedVideo = { video with views = video.views + 1 };
              videos.put(session.video_id, updatedVideo);
              
              try {
                let transferResult = await Token.transfer(video.uploader, rewardPerView);
                switch (transferResult) {
                  case (#ok(_)) { #ok(()) };
                  case (#err(error)) { #err("Transfer failed") };
                };
              } catch (e) {
                #err("Transfer error")
              };
            };
          };
        };
      };
    };
  };

  public query func getVideos() : async [Video] {
    Iter.toArray(videos.vals());
  };

  public query func getVideoChunk(videoId : Text, index : Nat) : async ?Blob {
    switch (videos.get(videoId)) {
      case null null;
      case (?video) {
        switch (Array.find(video.chunks, func(chunk : FileChunk) : Bool { chunk.index == index })) {
          case null null;
          case (?foundChunk) ?foundChunk.chunk;
        };
      };
    };
  };

  public query func getUserVideos(user : Principal) : async [Text] {
    Option.get(userVideos.get(user), []);
  };

  public query func getRewardPerView() : async Nat {
    rewardPerView;
  };

  public shared(msg) func getUserBalance() : async Nat {
    await Token.balanceOf(msg.caller);
  };
}
