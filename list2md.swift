//
//  main.swift
//  SwiftWebFramworks
//
//  Created by 오민호 on 2018. 7. 5..
//  Copyright © 2018년 오민호. All rights reserved.
//

import Foundation

extension String {
    var trimmed : String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var contentString : String {
        return (try? String(contentsOfFile: self)) ?? ""
    }
    func appendLine(to url: URL) throws {
        try self.appending("\n").append(to: url)
    }
    func append(to url: URL) throws {
        let data = self.data(using: String.Encoding.utf8)
        try data?.append(to: url)
    }
}

extension Data {
    func append(to url: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: url)
        }
    }
}

protocol ResponseObj {}

struct CommitInfo : Codable, ResponseObj{
    struct Commit : Codable {
        struct Committer : Codable {
            let name : String
            let email : String
            let date : Date
        }
        let committer : Committer
    }
    let commit : Commit
}

struct Repo : Codable, ResponseObj {

    let name : String
    let fullName : String
    let defaultBranch : String
    let htmlUrl : URL
    let stargazersCount : Int
    let forksCount : Int
    let openIssuesCount : Int
    let description : String
    var commit : CommitInfo.Commit?

    enum CodingKeys: String, CodingKey {
        case name, description, commit
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case htmlUrl = "html_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
    }

    mutating func update(_ commit : CommitInfo.Commit) {
        self.commit = commit
    }

}




let access_token : String = {
    return "access_token.txt".contentString.trimmed
}()

let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

let jsonDecoder = JSONDecoder()
jsonDecoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
    let container = try decoder.singleValueContainer()
    let dateString = try container.decode(String.self)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    if let date = formatter.date(from: dateString) {
        return date
    }
    throw DecodingError.dataCorruptedError(in: container,
                                           debugDescription: "Cannot decode date string \(dateString)")
})

enum API {
    case repo(String)
    case commit(Repo)

    var url : URL? {
        switch self {
        case .repo (let fullName):
            return URL(string: "https://api.github.com/repos/\(fullName)?access_token=\(access_token)")
        case .commit (let repo):
            return URL(string: "https://api.github.com/repos/\(repo.fullName)/commits/\(repo.defaultBranch)?access_token=\(access_token)")
        }
    }

    func map(data : Data) -> ResponseObj? {
        switch self {
        case .repo:
            return try? jsonDecoder.decode(Repo.self, from: data)
        case .commit:
            return try? jsonDecoder.decode(CommitInfo.self, from: data)
        }
    }
}


enum RequestError : Error {
    case urlError
    case serverError
    case mappingError

    var localizedDescription: String {
        switch self {
        case .urlError:
            return "urlError"
        case .serverError:
            return "serverError"
        case .mappingError:
            return "mappingError"
        }
    }
}

struct Request {
    let api : API
    func req(successHandler : @escaping (ResponseObj) -> (),
             errorHandler : @escaping  (Error) -> ()) {
        guard let url = api.url else {
            errorHandler(RequestError.urlError)
            return
        }
        let sema = DispatchSemaphore(value: 0)
        let request = URLRequest(url: url)
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            defer {
                sema.signal()
            }
            guard let data = data, let response = response as? HTTPURLResponse else {
                 errorHandler(RequestError.serverError)
                return
            }
            guard response.statusCode == 200 else {
                errorHandler(RequestError.serverError)
                return
            }
            guard let responseObj = self.api.map(data: data) else {
                errorHandler(RequestError.mappingError)
                return
            }
            successHandler(responseObj)
        }.resume()
        sema.wait()
    }
}

let fullNames : [String] = {
    return "list.txt".contentString
        .split(separator: "\n")
        .filter {
            String($0).hasPrefix("https://github.com/")
        }.map {
            let repo_url = String($0).trimmed
            let sIdx = repo_url.index(repo_url.startIndex, offsetBy: 19)
            return String(repo_url[sIdx...])
    }
}()


let head = """
# Top Swift Web Frameworks inspired of [mingrammer/python-web-framework-stars](https://github.com/mingrammer/python-web-framework-stars)
A list of popular github projects related to Swift web framework (ranked by stars automatically)
Please update **list.txt** (via Pull Request)

| Project Name | Stars | Forks | Open Issues | Description | Last Commit |
| ------------ | ----- | ----- | ----------- | ----------- | ----------- |
"""
let tail = "\n*Last Automatic Update: "

func update(repos : [Repo], to url : URL) throws {
    try head.appendLine(to: url)
    for repo in repos {
        guard let commit = repo.commit else {continue}
        try "| [\(repo.name)](\(repo.htmlUrl) | \(repo.stargazersCount) | \(repo.forksCount) | \(repo.openIssuesCount) | \(repo.description) | \(commit.committer.date) |".appendLine(to: url)
    }
    let today = formatter.string(from: Date())
    try (tail + today + "*").appendLine(to: url)
}


func main() throws {
    var repos = [Repo]()
    for fullName in fullNames {
        Request(api: .repo(fullName)).req(successHandler: { (repo) in
            guard let repo = repo as? Repo else {
                return
            }
            repos.append(repo)
        }) { (error) in
            print(error)
        }
    }
    for i in 0..<repos.count {
        Request(api: .commit(repos[i])).req(successHandler: { commitInfo in
            guard let commitInfo = commitInfo as? CommitInfo else {
                return
            }
            repos[i].update(commitInfo.commit)
        }) { (error) in
            print(error)
        }
    }
    repos.sort { $0.stargazersCount > $1.stargazersCount }
    FileManager.default.createFile(atPath: "README.md", contents: nil)
    if let url = URL(string : "README.md") {
        do {
            try update(repos: repos, to : url)
        } catch {
            print("Cound not update to file")
        }
    }

}

try? main()
