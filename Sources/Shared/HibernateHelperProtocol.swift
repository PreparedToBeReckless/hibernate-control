import Foundation

@objc(HibernateHelperProtocol)
protocol HibernateHelperProtocol {
    func executeHibernateScript(at path: String, with reply: @escaping (Bool, String?) -> Void)
    func setACSleepTimer(minutes: Int, with reply: @escaping (Bool, String?) -> Void)
}