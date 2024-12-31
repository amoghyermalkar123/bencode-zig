pub const TorrentFile = struct {
    // Basic torrent metadata
    info_hash: [20]u8, // SHA1 hash of the info dictionary
    announce: []const u8, // Main tracker URL
    announce_list: ?[][]const u8 = null, // Optional list of backup trackers
    creation_date: ?i64 = null, // Unix timestamp when the torrent was created
    comment: ?[]const u8 = null, // Optional comment
    created_by: ?[]const u8 = null, // Optional client/creator information
    encoding: ?[]const u8 = null, // Optional character encoding
    info: Info,

    // Info dictionary
    pub const Info = struct {
        piece_length: u32, // Number of bytes per piece
        pieces: []const u8, // Concatenated SHA1 hashes of all pieces
        private: ?bool = null, // Optional flag to disable DHT/PEX
        name: []const u8, // Suggested name for saving file/directory

        // Single file mode fields
        length: ?u64 = null, // Size of the file in bytes
        md5sum: ?[]const u8 = null, // Optional MD5 hash of the file

        // Multi file mode fields
        files: ?[]FileEntry = null, // List of files in the torrent

        pub const FileEntry = struct {
            length: u64, // Size of the file in bytes
            path: []const u8, // Path components of the file
            md5sum: ?[]const u8 = null, // Optional MD5 hash
        };
    };
};
